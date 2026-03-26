//
//  CameraViewModel.swift
//  Core ML tutorial
//
//  Created by Johnson Elangbam on 3/22/26.
//

import Foundation
import AVFoundation
import Vision
import UIKit

class CameraViewModel: NSObject, ObservableObject {

    @Published var faceBoxes: [CGRect] = []
    @Published var capturedFace: UIImage?
    @Published var showNameInput: Bool = false
    @Published var attendanceRecords: [AttendanceRecord] = []
    @Published var recognizedName: String = ""
    @Published var showRecognitionBanner: Bool = false
    
    private let faceRecognitionService = FaceRecognitionService()
    private let faceDetectionService = FaceDetectionService()
    private let storageService = StorageService()
    private let cameraService = CameraService()
    private let speechService = SpeechService()
    
    var currentPixelBuffer: CVPixelBuffer?
    var cameraSession: AVCaptureSession {
        cameraService.session
    }
    
    override init() {
        super.init()
        setupBindings()
        cameraService.startSession()
        storageService.loadSavedFaces()
    }
    
    private func setupBindings() {
        
        cameraService.onFrameCaptured = { [weak self] pixelBuffer in
            guard let self = self else { return }
            
            self.currentPixelBuffer = pixelBuffer
            
            self.faceDetectionService.detectFaces(pixelBuffer: pixelBuffer) { observations in
                
                DispatchQueue.main.async {
                    self.faceBoxes = observations.map { $0.boundingBox }
                }
            }
        }
    }
    
    
    func captureFace(from box: CGRect) {
        
        guard let pixelBuffer = currentPixelBuffer else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        // Convert normalized → pixel rect
        var rect = VNImageRectForNormalizedRect(box, Int(width), Int(height))
        
        // 🔥 Add padding (IMPORTANT)
        let padding: CGFloat = 0.3   // 30% padding
        
        let side = max(rect.width, rect.height)

        let squareRect = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )

        // Clamp again
        rect = squareRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        
        let newWidth = rect.width * (1 + padding)
        let newHeight = rect.height * (1 + padding)
        
        let newX = rect.origin.x - (newWidth - rect.width) / 2
        let newY = rect.origin.y - (newHeight - rect.height) / 2
        
        rect = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
        
        // 🔥 Clamp to image bounds (VERY IMPORTANT)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        
        print("Crop rect:", rect)
        
        let cropped = ciImage.cropped(to: rect)
        
        let context = CIContext()
        
        if let cgImage = context.createCGImage(cropped, from: cropped.extent) {
            
            let uiImage = UIImage(
                cgImage: cgImage,
                scale: 1.0,
                orientation: .leftMirrored
            )
            
            DispatchQueue.main.async {
                self.handleCapturedFace(uiImage)
            }
        }
    }
    
    func handleCapturedFace(_ image: UIImage) {
        
        let name = faceRecognitionService.recognizeFace(
            image,
            from: storageService.savedFaces
        )
        
        
        print("Recognized: \(name)")
        
        DispatchQueue.main.async {
            if name == "Unknown" && self.capturedFace == nil {
                // ❌ New user
                self.capturedFace = image
                self.showNameInput = true
                
                self.recognizedName = "New Face Detected"
                self.showRecognitionBanner = true
                
                // 🔥 Voice feedback
                self.speechService.speak("Face not recognized. Please register.")
                
            } else {
                // ✅ Known user
                self.recognizedName = "\(name) marked present"
                self.showRecognitionBanner = true
                
                self.markAttendance(name: name)
                
                // 🔥 Voice feedback
                self.speechService.speak("Welcome \(name)")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.showRecognitionBanner = false
                }
            }
        }
    }
    
    func markAttendance(name: String) {
        
        let record = AttendanceRecord(name: name, date: Date())
        attendanceRecords.append(record)
        
        print("Attendance marked for \(name)")
    }
    
    
    func saveFace(name: String) {
        
        guard let face = capturedFace,
              let embedding = faceRecognitionService.getEmbedding(from: face) else { return }
        
        _ = storageService.saveFace(
            name: name,
            image: face,
            embedding: embedding
        )
        
        // Update UI state
        capturedFace = nil
        showNameInput = false
    }
    
    
    func handleTap(at point: CGPoint, in size: CGSize) {
        
        for box in faceBoxes {
            
            let rect = VNImageRectForNormalizedRect(
                box,
                Int(size.width),
                Int(size.height)
            )
            
            let correctedRect = CGRect(
                x: rect.origin.x,
                y: size.height - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            
            if correctedRect.contains(point) {
                print("Face tapped ✅")
                captureFace(from: box)
                return
            }
        }
        
        print("No face tapped")
    }

    
    func cancelFaceRegistration() {
        
        // Clear captured data
        capturedFace = nil
        
        // Close sheet
        showNameInput = false
        
        // Reset UI state
        recognizedName = ""
        showRecognitionBanner = false
        
        // Optional: reset last spoken text so next scan speaks again
        speechService.reset()
        
        print("Face registration cancelled")
    }
    
}
