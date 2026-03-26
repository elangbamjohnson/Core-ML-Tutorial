//
//  CameraService.swift
//  Core ML tutorial
//
//  Created by Johnson on 26/03/26.
//

import Foundation
import AVFoundation

class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    var onFrameCaptured: ((CVPixelBuffer) -> Void)?
    
    func startSession() {
        
        sessionQueue.async {
            
            self.session.sessionPreset = .photo
            
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            ),
            let input = try? AVCaptureDeviceInput(device: device) else { return }
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.queue"))
            
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }
            
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            self.session.stopRunning()
        }
    }
    
    // MARK: - Frame Delegate
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        onFrameCaptured?(pixelBuffer)
    }
}
