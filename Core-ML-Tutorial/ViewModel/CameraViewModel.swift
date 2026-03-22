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

class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var result: String = "Scanning..."
    
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
        classifyFrame(pixelBuffer)
    }
    
    func classifyFrame(_ pixelBuffer: CVPixelBuffer) {
        
        do {
            let config = MLModelConfiguration()
            let model = try MobileNetV2(configuration: config)
            let visionModel = try VNCoreMLModel(for: model.model)
            
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                guard let results = request.results as? [VNClassificationObservation],
                      let topResult = results.first else { return }
                
                DispatchQueue.main.async {
                    self.result = "\(topResult.identifier) (\(Int(topResult.confidence * 100))%)"
                }
            }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            try handler.perform([request])
        } catch {
            print(error)
            
        }
    }
}
