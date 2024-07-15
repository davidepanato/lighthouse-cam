import UIKit
import AVFoundation
import os.log
import Vision

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // Capture session for managing input and output data streams
    var captureSession: AVCaptureSession?
    // Layer for displaying video preview
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    // Logger for logging events
    let logger = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Camera")
    
    // View to highlight the brightest point
    var highlightView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        os_log("viewDidLoad called", log: logger, type: .info)
        
        // Initialize the capture session
        captureSession = AVCaptureSession()
        
        // Get the default video capture device (camera)
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            os_log("Unable to access the camera", log: logger, type: .error)
            return
        }
        
        do {
            // Create input object from the capture device
            let input = try AVCaptureDeviceInput(device: captureDevice)
            // Add the input to the capture session
            captureSession?.addInput(input)
        } catch let error {
            os_log("Error setting up camera input: %{public}@", log: logger, type: .error, error.localizedDescription)
            return
        }
        
        // Create an output object for video data
        let output = AVCaptureVideoDataOutput()
        // Set the sample buffer delegate to self
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        // Add the output to the capture session
        captureSession?.addOutput(output)
        
        // Create and configure the video preview layer
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        videoPreviewLayer?.videoGravity = .resizeAspectFill
        videoPreviewLayer?.frame = view.layer.bounds
        view.layer.addSublayer(videoPreviewLayer!)
        
        // Start the capture session
        captureSession?.startRunning()
        
        // Get the screen size
        let screenSize = UIScreen.main.bounds
        
        // Set the size and position of the highlight view (a red circle)
        let rectWidth = 40.0
        let rectHeight = 40.0
        let xPosition = (screenSize.size.width - rectWidth) / 2
        let yPosition = (screenSize.size.height - rectHeight) / 2
        highlightView = UIView(frame: CGRect(x: xPosition, y: yPosition, width: rectWidth, height: rectHeight))
        highlightView?.layer.borderColor = UIColor.red.cgColor
        highlightView?.layer.borderWidth = 5
        highlightView?.layer.cornerRadius = 40
        highlightView?.isHidden = false
        view.addSubview(highlightView!)
        
        os_log("Camera session started", log: logger, type: .info)
    }
    
    // This method is called each time a frame is captured
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("Unable to get image buffer from sample buffer", log: logger, type: .error)
            return
        }
        
        // Convert the pixel buffer to CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            os_log("Unable to create CGImage from CIImage", log: logger, type: .error)
            return
        }
        
        // Find the brightest point in the image
        var brightestPoint = findBrightestPoint(in: cgImage)
        
        if let brightestPoint = brightestPoint {
            os_log("Brightest point detected at (x: %{public}f, y: %{public}f)", log: logger, type: .info, brightestPoint.x, brightestPoint.y)
            
            // Convert the point to the coordinate system of the view
            let convertedPoint = convertPoint(from: brightestPoint)
            let newCenterX = CGFloat(convertedPoint.x)
            if newCenterX > 393 {
                os_log("X out of bound", log: logger, type: .error)
            }
            let newCenterY = CGFloat(convertedPoint.y)
            if newCenterY > 852 {
                os_log("Y out of bound", log: logger, type: .error)
            }
            // Update the position of the highlight view on the main thread
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.3) {
                    self.highlightView?.center = CGPoint(x: newCenterX, y: newCenterY)
                }
            }
        } else {
            os_log("No bright point detected", log: logger, type: .info)
        }
    }
    
    // Function to find the brightest point in a given image
    func findBrightestPoint(in image: CGImage) -> CGPoint? {
        let startTime = DispatchTime.now().uptimeNanoseconds
        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        os_log("Enter findBrightestPoint", log: logger, type: .error)
        
        // Create a bitmap context
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            os_log("Unable to create CGContext", log: logger, type: .error)
            return nil
        }
        
        // Draw the image into the context
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Get pixel data from the context
        guard let pixelData = context.data else {
            os_log("Unable to get pixel data from CGContext", log: logger, type: .error)
            return nil
        }
        
        // Initialize variables for finding the brightest point
        let blockWidth = 10
        let blockHeight = 10
        let numBlocksX = width / blockWidth
        let numBlocksY = height / blockHeight
        var maxBrightness: CGFloat = 0
        var brightestPoint: CGPoint?
        
        let startTime2 = DispatchTime.now().uptimeNanoseconds
        for blockY in 0..<numBlocksY {
            for blockX in 0..<numBlocksX {
                var totalBrightness: CGFloat = 0
                
                // Calculate the average brightness of the block
                for y in (blockY * blockHeight)..<(blockY * blockHeight + blockHeight) {
                    for x in (blockX * blockWidth)..<(blockX * blockWidth + blockWidth) {
                        let pixelIndex = (y * bytesPerRow) + (x * 4)
                        let red = CGFloat(pixelData.load(fromByteOffset: pixelIndex, as: UInt8.self))
                        let green = CGFloat(pixelData.load(fromByteOffset: pixelIndex + 1, as: UInt8.self))
                        let blue = CGFloat(pixelData.load(fromByteOffset: pixelIndex + 2, as: UInt8.self))
                        totalBrightness += (red + green + blue) / (3.0 * 255.0)
                    }
                }
                
                // Check if the current block is the brightest one
                if totalBrightness > maxBrightness {
                    maxBrightness = totalBrightness
                    let centerX = CGFloat(blockX * blockWidth + (blockWidth / 2))
                    let centerY = 1080 - CGFloat(blockY * blockHeight + (blockHeight / 2))
                    brightestPoint = CGPoint(x: centerY, y: centerX) // values wrapped for landscape
                }
            }
        }
        let endTime2 = DispatchTime.now().uptimeNanoseconds
        let executionTime2 = Double(endTime2 - startTime2) / 1_000_000
        os_log("Execution time of for: %.2f milliseconds %.2f brightness", log: logger, type: .info, executionTime2, maxBrightness)

        let endTime = DispatchTime.now().uptimeNanoseconds
        let executionTime = Double(endTime - startTime) / 1_000_000 // Convert nanoseconds to milliseconds

        os_log("Execution time of findBrightestPoint: %.2f milliseconds %.2f brightness", log: logger, type: .info, executionTime, maxBrightness)

        os_log("Exit findBrightestPoint", log: logger, type: .error)
        return brightestPoint
    }
    
    // Function to convert a point from the image coordinate system to the view coordinate system
    func convertPoint(from point: CGPoint) -> CGPoint {
        let widthScale = CGFloat(1080.0 / 393.0) // Screen width to preview layer width ratio
        let heightScale = CGFloat(1920.0 / 852.0) // Screen height to preview layer height ratio
        return CGPoint(x: point.x / widthScale, y: point.y / heightScale)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        os_log("viewDidLayoutSubviews called", log: logger, type: .info)
        // Update the frame of the video preview layer
        videoPreviewLayer?.frame = view.layer.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop the capture session when the view is about to disappear
        captureSession?.stopRunning()
        os_log("Camera session stopped", log: logger, type: .info)
    }
}
