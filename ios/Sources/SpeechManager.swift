import AVFoundation
import Foundation

/// Spoken whispers via AVSpeechSynthesizer. The audio session uses plain
/// playback, so iOS routes through the glasses' speakers automatically when
/// they are connected as the Bluetooth audio device.
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    @Published var speakAloud = true

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard speakAloud, !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers]
        )
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func deactivateIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.deactivateIfIdle() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.deactivateIfIdle() }
    }
}
