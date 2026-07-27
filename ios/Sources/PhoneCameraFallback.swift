import AVFoundation
import UIKit

/// One-shot rear-camera capture used when glasses aren't connected —
/// keeps the whole capture loop working with zero hardware so the demo
/// never blocks.
///
/// The two settings at the top of `configure()` are the fix for "the mic and
/// the camera don't work at the same time": by default an AVCaptureSession
/// takes over the application's AVAudioSession and re-categorises it when it
/// starts, which silently killed the running speech recognition. Telling it not
/// to configure the audio session leaves `AudioSessionController`'s
/// `.playAndRecord` session untouched.
///
/// The session is also left running between shots, so a repeated capture
/// doesn't pay the start-up cost — or risk another audio interruption — every
/// time round the loop.
final class PhoneCameraFallback: NSObject, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var configured = false

    private func configure() {
        guard !configured else { return }
        session.beginConfiguration()
        // Never let the capture session touch our audio session.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.usesApplicationAudioSession = true
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(output)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
    }

    func capture() async -> UIImage? {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else { return nil }
        configure()
        guard !session.inputs.isEmpty else { return nil }
        if !session.isRunning {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.startRunning()
                    continuation.resume()
                }
            }
            // Let exposure/white balance settle so the first frame of a demo
            // isn't a black rectangle the face detector can't use.
            try? await Task.sleep(for: .milliseconds(350))
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(
                with: AVCapturePhotoSettings(),
                delegate: self
            )
        }
    }

    /// Explicit teardown — the capture loop keeps the camera warm otherwise.
    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .utility).async { self.session.stopRunning() }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        continuation?.resume(returning: image)
        continuation = nil
        // Session intentionally left running.
    }
}
