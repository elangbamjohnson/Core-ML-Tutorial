//
//  CameraViewModel.swift
//  Core ML tutorial
//
//  Created by Johnson Elangbam on 3/22/26.
//

import Foundation
import AVFoundation
import Vision
import CoreML
import UIKit
import Vision

class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var result: String = "Scanning..."
    @Published var faceBoxes: [CGRect] = []
    private var recentPredictions: [String] = []
    private var lastPredictionTime = Date()
    
    
    let session = AVCaptureSession()
    
    override init() {
        super.init()
        setupCamera()
    }
    
    func setupCamera() {
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(for: .video),
        let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        session.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.queue"))
        
        session.addOutput(output)
        session.startRunning()
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        detectFaces(pixelBuffer)
        
    }
    
    func detectFaces(_ pixelBuffer: CVPixelBuffer) {
        
        let request = VNDetectFaceRectanglesRequest { request, error in
            
            guard let observations = request.results as? [VNFaceObservation] else { return }
            
            let boxes = observations.map { observation -> CGRect in
                return observation.boundingBox
            }
            
            DispatchQueue.main.async {
                self.faceBoxes = boxes
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        
        try? handler.perform([request])
    }
    
    
    func classifyFrame(_ pixelBuffer: CVPixelBuffer) {
        
        do {
            let config = MLModelConfiguration()
            let model = try MobileNetV2(configuration: config)
            let visionModel = try VNCoreMLModel(for: model.model)
            
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                
                guard let observations = request.results as? [VNClassificationObservation] else { return }
                
                // 🔥 1. Confidence filtering
                let filtered = observations.filter { $0.confidence > 0.4 }
                
                // 🔥 2. Take top result after filtering
                guard let topResult = filtered.first else {
                    DispatchQueue.main.async {
                        self.result = "Not confident enough 🤔"
                    }
                    return
                }
                
                let label = topResult.identifier
                
                DispatchQueue.main.async {
                    
                    // 🔥 3. Temporal smoothing
                    self.recentPredictions.append(label)
                    
                    if self.recentPredictions.count > 5 {
                        self.recentPredictions.removeFirst()
                    }
                    
                    let mostCommon = self.recentPredictions
                        .reduce(into: [:]) { counts, label in
                            counts[label, default: 0] += 1
                        }
                        .max(by: { $0.value < $1.value })?.key
                    
                    self.result = "\(mostCommon ?? label) (\(Int(topResult.confidence * 100))%)"
                }
            }
            
            // 🔥 4. Improve image preprocessing
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            try handler.perform([request])
            
        } catch {
            print(error)
        }
    }
}
