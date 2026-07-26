import AVFoundation
import Foundation
import Speech

/// Push-to-talk live speech-to-text over SFSpeechRecognizer + AVAudioEngine.
///
/// The transcript is published as it arrives so the Listen tab can show the
/// conversation building up in real time; on stop the final text is handed to
/// /walker/ingest. Everything is @MainActor and recognition callbacks hop back
/// onto the main actor, so the published state is always safe to read in SwiftUI.
@MainActor
final class DictationManager: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorText: String?
    /// Rough input level 0…1, for the pulsing mic.
    @Published private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: Permissions

    private func requestSpeechAuth() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicAuth() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: Control

    func start() async {
        guard !isRecording else { return }
        errorText = nil
        transcript = ""

        guard await requestSpeechAuth() else {
            errorText = "Speech recognition permission was denied — enable it in Settings."
            return
        }
        guard await requestMicAuth() else {
            errorText = "Microphone permission was denied — enable it in Settings."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Speech recognition isn't available right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) {
                [weak self] buffer, _ in
                request.append(buffer)
                let peak = Self.peak(of: buffer)
                Task { @MainActor in self?.level = peak }
            }

            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let failed = error != nil
                let done = result?.isFinal ?? false
                Task { @MainActor in
                    guard let self else { return }
                    if let text, !text.isEmpty { self.transcript = text }
                    if failed || done {
                        // A recognizer error after the user already stopped is
                        // routine (end of audio); only surface it while live.
                        if failed, self.isRecording, self.transcript.isEmpty {
                            self.errorText = "Didn't catch that — try again."
                        }
                        self.teardownAudio()
                    }
                }
            }
        } catch {
            errorText = "Couldn't start the microphone: \(error.localizedDescription)"
            teardownAudio()
        }
    }

    /// Stops capture and returns the final transcript.
    @discardableResult
    func stop() -> String {
        guard isRecording else { return transcript }
        isRecording = false
        request?.endAudio()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0
        // The task finishes asynchronously; the last partial we already hold is
        // the transcript we submit, so the demo never waits on the final callback.
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        transcript = ""
        errorText = nil
    }

    /// Lets the demo run in the simulator, or after a mic mishap, by typing.
    func setTranscript(_ text: String) {
        transcript = text
    }

    private func teardownAudio() {
        guard isRecording || engine.isRunning else { return }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0
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
