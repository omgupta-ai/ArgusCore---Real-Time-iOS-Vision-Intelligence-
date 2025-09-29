import UIKit
import Vision
import CoreML
import AVFoundation // Import the framework for camera access

// We're still using the same model, so this line doesn't change.
typealias ImageClassifier = MobileNetV2

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - UI Components

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "ArgusCore"
        label.font = .systemFont(ofSize: 34, weight: .bold)
        label.textAlignment = .center
        // Make text visible against a live camera feed
        label.textColor = .white
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 1, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let resultLabel: UILabel = {
        let label = UILabel()
        label.text = "Waiting for camera..."
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        // Make text visible against a live camera feed
        label.backgroundColor = UIColor(white: 0, alpha: 0.5)
        label.textColor = .white
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // This layer will show the camera feed.
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    // This manages the camera input and output.
    private let captureSession = AVCaptureSession()

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Make sure the preview layer fills the screen after rotation, etc.
        previewLayer?.frame = view.bounds
    }

    // MARK: - Core ML Logic (This part is mostly the same!)

    lazy var classificationRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: ImageClassifier().model)
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            }
            request.imageCropAndScaleOption = .centerCrop
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    func processClassifications(for request: VNRequest, error: Error?) {
        // We're already on a background thread, so we switch to main to update the UI.
        DispatchQueue.main.async {
            guard let results = request.results else {
                self.resultLabel.text = "Unable to classify.\n\(error?.localizedDescription ?? "Error")"
                return
            }
            
            let classifications = results as? [VNClassificationObservation]

            if let classifications = classifications, !classifications.isEmpty {
                let topClassifications = classifications.prefix(2).map {
                    String(format: "%@: %.0f%%", $0.identifier.components(separatedBy: ",")[0], $0.confidence * 100)
                }
                self.resultLabel.text = topClassifications.joined(separator: "\n")
            } else {
                self.resultLabel.text = "Nothing recognized."
            }
        }
    }
    
    // MARK: - Camera Setup and Frame Processing

    private func setupCamera() {
        // 1. Get the back camera.
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        // 2. Create an input from the device.
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        captureSession.addInput(input)
        
        // 3. Create the preview layer and add it to the view.
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.bounds
        
        // Bring UI labels to the front
        view.bringSubviewToFront(titleLabel)
        view.bringSubviewToFront(resultLabel)

        // 4. Create a video data output.
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        
        // 5. Start the session.
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    // This is the delegate method that gets called for every frame the camera captures.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 1. Get the pixel buffer from the frame.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 2. Create a Vision request handler.
        var requestOptions: [VNImageOption: Any] = [:]
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }
        
        // 3. Perform the request.
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: requestOptions)
        try? imageRequestHandler.perform([self.classificationRequest])
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(resultLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            resultLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }
}
