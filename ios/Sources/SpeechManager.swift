import AVFoundation
import Foundation

/// Speaks the recall line via AVSpeechSynthesizer.
///
/// It deliberately does NOT touch AVAudioSession. The session is owned by
/// `AudioSessionController` (`.playAndRecord` + `.defaultToSpeaker` +
/// `.allowBluetooth`, activated once at launch), so speaking routes to the
/// glasses' speakers when they are connected and to the phone speaker when
/// they aren't — without ever deactivating the session out from under the
/// microphone. That deactivation is what used to kill live transcription the
/// moment a recall line was read out.
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    @Published var speakAloud = true
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speakAloud, !line.isEmpty else { return }
        // Make sure the session is live, but never re-categorise it.
        AudioSessionController.shared.reassert()
        isSpeaking = true
        AudioSessionController.shared.isSpeaking = true
        let utterance = AVSpeechUtterance(string: line)
        utterance.rate = 0.48
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finished()
    }

    private func finished() {
        guard !synthesizer.isSpeaking else { return }
        isSpeaking = false
        AudioSessionController.shared.isSpeaking = false
        // No setActive(false) here, on purpose.
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finished() }
    }
}
