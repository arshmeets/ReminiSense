import AVFoundation
import Foundation

/// One AVAudioSession for the whole app, configured once and left active.
///
/// Why this exists: the demo needs the microphone (SFSpeechRecognizer), the
/// speaker (AVSpeechSynthesizer TTS) and a camera capture to work in the same
/// second. Previously DictationManager and SpeechManager each set their own
/// category and each called `setActive(false)` when they finished, so whoever
/// stopped last tore the session out from under whoever was still running —
/// that is why the mic and the camera "don't work at the same time".
///
/// Rules enforced here:
///  * category is `.playAndRecord` with `.defaultToSpeaker` + `.allowBluetooth`
///    so the mic keeps working while TTS plays and audio routes to the glasses
///    when they are the Bluetooth device.
///  * `setActive(true)` happens exactly once, at launch.
///  * `setActive(false)` is never called by feature code. Nothing deactivates
///    the session for the lifetime of the app.
@MainActor
final class AudioSessionController: ObservableObject {
    static let shared = AudioSessionController()

    /// Human-readable state for the UI so a failure is visible, not silent.
    @Published private(set) var status = "audio session: not configured yet"
    @Published private(set) var isActive = false
    /// True while TTS is talking. The dictation tap drops buffers during this
    /// window so Recall never transcribes its own voice.
    @Published var isSpeaking = false

    /// Bumped whenever the audio route changes (glasses connect/disconnect,
    /// headphones in/out). Listeners rebuild their engine graph, because the
    /// input node's format is invalid after a route change.
    @Published private(set) var routeGeneration = 0

    private var configured = false

    private init() {}

    /// Configure + activate. Safe to call repeatedly; only the first call does
    /// the work. Called from the App initializer path at launch.
    @discardableResult
    func activate() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if !configured {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [
                        .defaultToSpeaker,
                        .allowBluetooth,
                        .allowBluetoothA2DP,
                        .duckOthers,
                    ]
                )
                observeRouteChanges()
                configured = true
            }
            try session.setActive(true, options: [])
            isActive = true
            status = "audio session: active · \(routeDescription)"
            return true
        } catch {
            isActive = false
            status = "audio session failed: \(error.localizedDescription)"
            print("[recall] \(status)")
            return false
        }
    }

    /// Re-assert the session without tearing it down — used after an
    /// interruption (phone call, Siri) or a camera capture that stole the
    /// route. Never deactivates.
    func reassert() {
        guard configured else {
            activate()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isActive = true
            status = "audio session: active · \(routeDescription)"
        } catch {
            status = "audio session re-activate failed: \(error.localizedDescription)"
            print("[recall] \(status)")
        }
    }

    var routeDescription: String {
        let route = AVAudioSession.sharedInstance().currentRoute
        let out = route.outputs.first?.portName ?? "—"
        let mic = route.inputs.first?.portName ?? "—"
        return "in: \(mic) · out: \(out)"
    }

    private func observeRouteChanges() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.routeGeneration += 1
                self.status = "audio session: active · \(self.routeDescription)"
            }
        }

        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard
                    let self,
                    let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey]
                        as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: raw)
                else { return }
                if type == .ended {
                    self.reassert()
                    self.routeGeneration += 1
                }
            }
        }

        center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.configured = false
                self.activate()
                self.routeGeneration += 1
            }
        }
    }
}
