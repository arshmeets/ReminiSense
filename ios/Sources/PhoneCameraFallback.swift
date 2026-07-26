import AVFoundation
import UIKit

/// One-shot rear-camera capture used when glasses aren't connected —
/// keeps the whole capture loop working with zero hardware so the demo
/// never blocks.
final class PhoneCameraFallback: NSObject, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    override init() {
        super.init()
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(output)
        else { return }
        session.addInput(input)
        session.addOutput(output)
    }

    func capture() async -> UIImage? {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted, !session.inputs.isEmpty else { return nil }
        if !session.isRunning {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.startRunning()
                    continuation.resume()
                }
            }
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(
                with: AVCapturePhotoSettings(),
                delegate: self
            )
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        continuation?.resume(returning: image)
        continuation = nil
        session.stopRunning()
    }
}
