import AVFoundation
import Combine
import Foundation
import Speech

/// Live speech-to-text over SFSpeechRecognizer + AVAudioEngine.
///
/// This is a single shared instance because the audio engine and its input tap
/// are process-wide resources. Two DictationManagers (one per tab) would fight
/// over `inputNode`, which is what made the mic look broken.
///
/// Design rules, all of which exist because of an on-stage failure:
///  * the audio session is owned by `AudioSessionController` and is NEVER
///    deactivated here — a photo capture or a TTS line no longer kills the mic.
///  * the engine is started and the tap installed ONCE (`prime()`); start/stop
///    only create and finish the recognition *task*. Stopping does not touch
///    the engine, so the next capture starts instantly.
///  * on-device recognition is preferred when the device supports it, so bad
///    conference Wi-Fi cannot break transcription. If the on-device task fails
///    immediately we retry once over the network.
///  * SFSpeechRecognizer drops an audio-buffer task after ~1 minute; a watchdog
///    rolls the task over at 50s and keeps the text captured so far.
///  * authorization state is published so a denied permission is visible in the
///    UI instead of failing silently.
/// Thread-safe handle on the live recognition request.
///
/// The input tap fires on a realtime audio thread and the buffer it hands over
/// is only valid for the duration of that callback — hopping to the main actor
/// before calling `append` loses audio. So the tap appends synchronously
/// through this box, which is the only piece of state shared with the audio
/// thread.
private final class RecognitionSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var accepting = false
    private var muted = false

    func open(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock()
        self.request = request
        accepting = true
        lock.unlock()
    }

    func close() {
        lock.lock()
        accepting = false
        request = nil
        lock.unlock()
    }

    /// Drops audio while TTS is talking so Recall never transcribes itself.
    func setMuted(_ value: Bool) {
        lock.lock()
        muted = value
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        let target = (accepting && !muted) ? request : nil
        lock.unlock()
        target?.append(buffer)
        return target != nil
    }
}

@MainActor
final class DictationManager: ObservableObject {
    static let shared = DictationManager()

    // MARK: Published state

    /// Everything heard this session: finished segments + the live partial.
    @Published private(set) var transcript = ""
    /// Just the current recognition task's partial, for the "live" line.
    @Published private(set) var partial = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorText: String?
    /// Rough input level 0…1, for the pulsing mic.
    @Published private(set) var level: Double = 0
    /// Non-nil once permissions have been asked for at launch.
    @Published private(set) var speechAuth: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var micGranted = false
    @Published private(set) var engineRunning = false
    /// Free-text diagnostic shown in Connect.
    @Published private(set) var diagnostic = "mic: not started"

    // MARK: Internals

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let sink = RecognitionSink()
    private var muteObserver: AnyCancellable?
    private var tapInstalled = false
    private var committed = ""
    private var taskStartedAt: Date?
    private var watchdog: Task<Void, Never>?
    private var routeObserver: AnyCancellable?
    /// Set when we are rolling the task over at the 1-minute limit, so the
    /// completion handler doesn't treat it as a user-visible failure.
    private var rollingOver = false
    private var usedOnDeviceForThisTask = false
    private var retriedOnNetwork = false

    private init() {
        routeObserver = AudioSessionController.shared.$routeGeneration
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.rebuildEngineAfterRouteChange() }
            }
        // Mirror the TTS flag into the audio-thread-safe sink.
        muteObserver = AudioSessionController.shared.$isSpeaking
            .sink { [sink] speaking in sink.setMuted(speaking) }
    }

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    /// One line describing whether the mic pipeline is actually usable.
    var authSummary: String {
        var bits: [String] = []
        switch speechAuth {
        case .authorized: bits.append("speech: allowed")
        case .denied: bits.append("speech: DENIED — enable in Settings › Recall")
        case .restricted: bits.append("speech: restricted on this device")
        case .notDetermined: bits.append("speech: not asked yet")
        @unknown default: bits.append("speech: unknown")
        }
        bits.append(micGranted ? "mic: allowed" : "mic: DENIED — enable in Settings › Recall")
        bits.append(isAvailable ? "recognizer: available" : "recognizer: unavailable")
        if supportsOnDevice { bits.append("on-device: yes") }
        return bits.joined(separator: " · ")
    }

    var isUsable: Bool {
        speechAuth == .authorized && micGranted && isAvailable
    }

    // MARK: Permissions — asked once, at launch

    /// Requests speech + microphone authorization and records the outcome.
    /// Called from the app's launch path so a denial is visible immediately
    /// rather than the first time the user holds the button on stage.
    func requestAuthorization() async {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechAuth = speech

        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        micGranted = mic

        diagnostic = authSummary
        print("[recall] \(diagnostic)")
    }

    // MARK: Engine lifecycle

    /// Starts the audio engine and installs the input tap. Idempotent — the
    /// tap is installed exactly once and survives photo captures, TTS and tab
    /// switches.
    @discardableResult
    func prime() -> Bool {
        guard !engine.isRunning else {
            engineRunning = true
            return true
        }
        guard AudioSessionController.shared.isActive
            || AudioSessionController.shared.activate()
        else {
            errorText = "Audio session wouldn't activate — restart the app."
            return false
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorText = "The microphone reported an empty format — unplug/reconnect audio and try again."
            diagnostic = "mic: invalid input format (\(format.sampleRate) Hz)"
            return false
        }

        if !tapInstalled {
            let sink = self.sink
            input.installTap(onBus: 0, bufferSize: 1024, format: format) {
                [weak self] buffer, _ in
                // The tap is permanent and appends on THIS thread — the buffer
                // is not valid past the callback. Only the UI level hops to the
                // main actor.
                let live = sink.append(buffer)
                let peak = Self.peak(of: buffer)
                Task { @MainActor in self?.level = live ? peak : 0 }
            }
            tapInstalled = true
        }

        do {
            engine.prepare()
            try engine.start()
            engineRunning = true
            diagnostic = "mic: engine running @ \(Int(format.sampleRate)) Hz · \(AudioSessionController.shared.routeDescription)"
            return true
        } catch {
            engineRunning = false
            errorText = "Couldn't start the microphone: \(error.localizedDescription)"
            diagnostic = "mic: engine failed — \(error.localizedDescription)"
            return false
        }
    }

    /// Full teardown. Only used when leaving the app; the demo never calls it.
    func shutdown() {
        stopTask()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        engineRunning = false
        diagnostic = "mic: stopped"
    }

    private func rebuildEngineAfterRouteChange() {
        // A route change invalidates the input node's format; the tap has to be
        // reinstalled or buffers stop arriving (this is what happened when the
        // glasses connected mid-session).
        let wasRecording = isRecording
        let carried = transcript
        stopTask()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        engineRunning = false
        AudioSessionController.shared.reassert()
        guard prime() else { return }
        if wasRecording {
            // `carried` already includes the partial, so clear it first or
            // beginTask()'s commit would count that text twice.
            partial = ""
            committed = carried
            beginTask()
        }
    }

    // MARK: Control

    /// Begin (or resume) capturing. Keeps whatever was already transcribed if
    /// `keepExisting` is true — used when a capture appends to a session.
    func start(keepExisting: Bool = false) async {
        guard !isRecording else { return }
        errorText = nil
        if !keepExisting {
            committed = ""
            transcript = ""
            partial = ""
        }

        if speechAuth == .notDetermined || !micGranted {
            await requestAuthorization()
        }
        guard speechAuth == .authorized else {
            errorText = "Speech recognition is off for Recall — Settings › Recall › Speech Recognition."
            return
        }
        guard micGranted else {
            errorText = "Microphone access is off for Recall — Settings › Recall › Microphone."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Speech recognition isn't available right now (no network and no on-device model)."
            return
        }
        guard prime() else { return }

        retriedOnNetwork = false
        beginTask()
    }

    /// Creates a fresh recognition request + task against the already-running
    /// engine. Used by `start()` and by the 1-minute rollover.
    private func beginTask(forceNetwork: Bool = false) {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        let onDevice = !forceNetwork && recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice
        usedOnDeviceForThisTask = onDevice
        self.request = request
        sink.open(request)

        // Whatever the previous task produced becomes a finished segment here,
        // and ONLY here. Committing anywhere else double-counts, because a
        // recognition task's `bestTranscription` is cumulative and a final
        // result can land after stop() and re-populate `partial`.
        commitPartial()

        isRecording = true
        taskStartedAt = Date()
        partial = ""
        diagnostic = "mic: listening (\(onDevice ? "on-device" : "network"))"

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    self.partial = text
                    self.recomputeTranscript()
                }
                if failure != nil || isFinal {
                    self.handleTaskEnd(error: failure, isFinal: isFinal)
                }
            }
        }

        startWatchdog()
    }

    private func handleTaskEnd(error: Error?, isFinal: Bool) {
        // A rollover ends the old task on purpose — not an error.
        if rollingOver { return }

        if let error, isRecording, partial.isEmpty, transcript.isEmpty {
            // On-device model missing/failing is common on a fresh device;
            // fall back to the network recognizer once before giving up.
            if usedOnDeviceForThisTask, !retriedOnNetwork {
                retriedOnNetwork = true
                diagnostic = "mic: on-device failed, retrying over network"
                task = nil
                request = nil
                beginTask(forceNetwork: true)
                return
            }
            errorText = "Didn't catch that — \(error.localizedDescription)"
            diagnostic = "mic: recognition error — \(error.localizedDescription)"
        }

        // Deliberately no commit here: `partial` already holds the whole of this
        // task's text, and it stays there until the next task starts. A final
        // result arriving after stop() just refines it in place.
        if !isRecording {
            request = nil
            task = nil
        }
    }

    /// Stops the recognition task and returns the final transcript. The engine,
    /// the tap and the audio session are all left alone on purpose.
    @discardableResult
    func stop() -> String {
        guard isRecording else { return transcript }
        isRecording = false
        level = 0
        watchdog?.cancel()
        watchdog = nil
        sink.close()
        request?.endAudio()
        task?.finish()
        // `partial` is left intact so the final result can refine it; the next
        // beginTask() is what turns it into a committed segment.
        taskStartedAt = nil
        diagnostic = "mic: idle (engine still running)"
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopTask() {
        isRecording = false
        watchdog?.cancel()
        watchdog = nil
        sink.close()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
    }

    /// Record for a fixed window and hand back what was said. This is what the
    /// one-tap Meet flow uses: no press-and-hold, no way to forget to release.
    func record(seconds: Double, keepExisting: Bool = false) async -> String {
        await start(keepExisting: keepExisting)
        guard isRecording else { return "" }
        let deadline = Date().addingTimeInterval(seconds)
        while isRecording, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        let text = stop()
        // The recognizer keeps refining for a beat after endAudio(); give it a
        // short grace window so the last few words make it in.
        try? await Task.sleep(for: .milliseconds(700))
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? text : transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        committed = ""
        partial = ""
        transcript = ""
        errorText = nil
    }

    /// Lets the demo run in the simulator, or after a mic mishap, by typing.
    func setTranscript(_ text: String) {
        committed = text
        partial = ""
        recomputeTranscript()
    }

    // MARK: 1-minute limit

    /// SFSpeechRecognizer abandons a buffer-fed task at roughly 60 seconds.
    /// Roll it over at 50 so a long conversation keeps transcribing.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while let self, self.isRecording {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.isRecording,
                    let started = self.taskStartedAt
                else { continue }
                if Date().timeIntervalSince(started) > 50 {
                    self.rollTaskOver()
                }
            }
        }
    }

    private func rollTaskOver() {
        rollingOver = true
        sink.close()
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
        rollingOver = false
        diagnostic = "mic: rolled the recognition task over at 50s"
        // beginTask() commits the partial from the task we just ended.
        beginTask(forceNetwork: !usedOnDeviceForThisTask)
    }

    // MARK: Text bookkeeping

    private func commitPartial() {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        committed = committed.isEmpty ? text : committed + " " + text
        partial = ""
        recomputeTranscript()
    }

    private func recomputeTranscript() {
        let joined = [committed, partial]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        transcript = joined
    }

    private nonisolated static func peak(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in stride(from: 0, to: count, by: 8) {
            sum += abs(channel[index])
        }
        let mean = Double(sum) / Double(max(1, count / 8))
        return min(1, mean * 12)
    }
}
