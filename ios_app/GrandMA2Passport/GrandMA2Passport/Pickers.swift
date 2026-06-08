import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import QuickLook

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        DebugLog.write("DocumentPicker makeUIViewController")
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.xml], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            DebugLog.write("DocumentPicker didPick count=\(urls.count)")
            guard let url = urls.first else { return }
            DebugLog.write("DocumentPicker picked \(url.absoluteString)")
            let scoped = url.startAccessingSecurityScopedResource()
            DebugLog.write("DocumentPicker scoped=\(scoped)")
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "xml" : url.pathExtension)
                if FileManager.default.fileExists(atPath: tmp.path) {
                    try FileManager.default.removeItem(at: tmp)
                }
                try FileManager.default.copyItem(at: url, to: tmp)
                DebugLog.write("DocumentPicker copied tmp \(tmp.path)")
                DispatchQueue.main.async {
                    DebugLog.write("DocumentPicker onPick tmp")
                    self.onPick(tmp)
                }
            } catch {
                DebugLog.write("DocumentPicker copy error \(error.localizedDescription)")
                DispatchQueue.main.async {
                    DebugLog.write("DocumentPicker onPick original")
                    self.onPick(url)
                }
            }
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    var device: UIImagePickerController.CameraDevice
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.cameraPosition = device == .front ? .front : .back
        controller.onPick = onPick
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.cameraPosition = device == .front ? .front : .back
    }
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var cameraPosition: AVCaptureDevice.Position = .back
    var onPick: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let shutter = UIButton(type: .custom)
    private let cancel = UIButton(type: .system)
    private let zoomSlider = UISlider()
    private let zoomLabel = UILabel()
    private let queue = DispatchQueue(label: "grandma2.camera.session")
    private var configured = false
    private var captureDevice: AVCaptureDevice?
    private var maxZoomFactor: CGFloat = 5

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreview()
        setupControls()
        requestAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        layoutControls()
        updateVideoOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func setupPreview() {
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(previewLayer)
        previewLayer.session = session
    }

    private func setupControls() {
        shutter.backgroundColor = .white
        shutter.layer.borderColor = UIColor(white: 1, alpha: 0.42).cgColor
        shutter.layer.borderWidth = 6
        shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        view.addSubview(shutter)

        cancel.setTitle("Закрыть", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .boldSystemFont(ofSize: 17)
        cancel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        cancel.layer.cornerRadius = 8
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)

        zoomLabel.text = "1x"
        zoomLabel.textColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1)
        zoomLabel.font = .boldSystemFont(ofSize: 16)
        zoomLabel.textAlignment = .center
        zoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        zoomLabel.layer.cornerRadius = 19
        zoomLabel.clipsToBounds = true
        view.addSubview(zoomLabel)

        zoomSlider.minimumValue = 1
        zoomSlider.maximumValue = 5
        zoomSlider.value = 1
        zoomSlider.minimumTrackTintColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1)
        zoomSlider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.25)
        zoomSlider.thumbTintColor = .white
        zoomSlider.addTarget(self, action: #selector(zoomChanged), for: .valueChanged)
        view.addSubview(zoomSlider)
    }

    private func layoutControls() {
        let safe = view.safeAreaInsets
        let landscape = view.bounds.width > view.bounds.height
        let size: CGFloat = landscape ? 74 : 82
        shutter.frame = CGRect(x: 0, y: 0, width: size, height: size)
        shutter.layer.cornerRadius = size / 2
        if landscape {
            shutter.center = CGPoint(x: view.bounds.width - safe.right - 78, y: view.bounds.midY)
            zoomSlider.frame = CGRect(x: view.bounds.width - safe.right - 132, y: view.bounds.midY + 76, width: 108, height: 34)
            zoomLabel.frame = CGRect(x: view.bounds.width - safe.right - 116, y: view.bounds.midY - 122, width: 76, height: 38)
        } else {
            shutter.center = CGPoint(x: view.bounds.midX, y: view.bounds.height - safe.bottom - 74)
            zoomSlider.frame = CGRect(x: safe.left + 42, y: view.bounds.height - safe.bottom - 146, width: view.bounds.width - safe.left - safe.right - 84, height: 34)
            zoomLabel.frame = CGRect(x: view.bounds.midX - 38, y: view.bounds.height - safe.bottom - 194, width: 76, height: 38)
        }

        cancel.frame = CGRect(x: safe.left + 16, y: safe.top + 14, width: 92, height: 38)
    }

    private func requestAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureSession() : self?.onCancel?()
                }
            }
        default:
            onCancel?()
        }
    }

    private func configureSession() {
        guard !configured else { return }
        configured = true
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                DispatchQueue.main.async { self.onCancel?() }
                self.session.commitConfiguration()
                return
            }
            self.captureDevice = device
            self.session.addInput(input)

            if self.session.canAddOutput(self.output), !self.session.outputs.contains(self.output) {
                self.session.addOutput(self.output)
            }
            self.output.isHighResolutionCaptureEnabled = true
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.configureZoom(for: device)
                self.updateVideoOrientation()
            }
        }
    }

    private func configureZoom(for device: AVCaptureDevice) {
        let deviceMax = min(device.activeFormat.videoMaxZoomFactor, 10)
        maxZoomFactor = max(1, min(deviceMax, 5))
        zoomSlider.minimumValue = 1
        zoomSlider.maximumValue = Float(maxZoomFactor)
        zoomSlider.value = 1
        zoomLabel.text = "1x"
        zoomSlider.isHidden = maxZoomFactor <= 1.05
        zoomLabel.isHidden = maxZoomFactor <= 1.05
    }

    private func updateVideoOrientation() {
        guard let connection = previewLayer.connection, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = currentOrientation()
    }

    private func currentOrientation() -> AVCaptureVideoOrientation {
        if view.bounds.width > view.bounds.height {
            return UIDevice.current.orientation == .landscapeRight ? .landscapeLeft : .landscapeRight
        }
        return .portrait
    }

    @objc private func takePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = currentOrientation()
        }
        shutter.isEnabled = false
        output.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func zoomChanged() {
        let factor = CGFloat(zoomSlider.value)
        zoomLabel.text = String(format: "%.1fx", factor).replacingOccurrences(of: ".0x", with: "x")
        queue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            let clamped = min(max(factor, 1), self.maxZoomFactor)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                DebugLog.write("Camera zoom error \(error.localizedDescription)")
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { shutter.isEnabled = true }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        onPick?(image)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    enum Source {
        case camera(UIImagePickerController.CameraDevice)
        case library
    }

    var source: Source
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        switch source {
        case .camera(let device):
            picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
            if UIImagePickerController.isCameraDeviceAvailable(device) {
                picker.cameraDevice = device
            }
        case .library:
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onPick(image)
            }
            picker.dismiss(animated: true)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FilePreview: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
