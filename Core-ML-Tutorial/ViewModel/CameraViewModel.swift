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

struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    var name: String = "Scanning..."
}

class CameraViewModel: NSObject, ObservableObject {

    @Published var faceBoxes: [CGRect] = []
    @Published var capturedFace: UIImage?
    @Published var showNameInput: Bool = false
    @Published var attendanceRecords: [AttendanceRecord] = []
    @Published var recognizedName: String = ""
    @Published var showRecognitionBanner: Bool = false
    @Published var detectedFaces: [DetectedFace] = []
    
    
    private let faceRecognitionService = FaceRecognitionService()
    private let faceDetectionService = FaceDetectionService()
    private let storageService = StorageService()
    private let cameraService = CameraService()
    private let speechService = SpeechService()
    private var lastRecognitionTime = Date()
    private let recognitionInterval: TimeInterval = 0.5
    private var recentPredictions: [String] = []
    private let predictionWindow = 5
    private var lastRecognizedName: String?
    private let recognitionCooldown: TimeInterval = 3.0
    private var lastFrameProcessTime = Date()
    private let frameInterval: TimeInterval = 0.5
    private var isCameraRunning = false
    
    var currentPixelBuffer: CVPixelBuffer?
    var cameraSession: AVCaptureSession {
        cameraService.session
    }
    
    override init() {
        super.init()
        setupBindings()
//        cameraService.startSession()
        storageService.loadSavedFaces()
    }
    
    private func setupBindings() {
        
        cameraService.onFrameCaptured = { [weak self] pixelBuffer in
            guard let self = self else { return }
            
            let now = Date()
            if now.timeIntervalSince(self.lastRecognitionTime) < self.recognitionInterval {
                return
            }
            self.lastRecognitionTime = now
            
            self.currentPixelBuffer = pixelBuffer
            
            self.faceDetectionService.detectFaces(pixelBuffer: pixelBuffer) { observations in
                
                // ✅ Build DetectedFace array
                var newDetectedFaces: [DetectedFace] = []
                
                for observation in observations {
                    let face = DetectedFace(
                        boundingBox: observation.boundingBox,
                        name: "Scanning..." // default state
                    )
                    newDetectedFaces.append(face)
                }
                
                DispatchQueue.main.async {
                    self.detectedFaces = newDetectedFaces   // ✅ THIS FIXES YOUR UI
                }
                
                // 🔥 Auto recognition (optional: first face only for now)
                guard let firstFace = observations.first else { return }
                
                if let faceImage = self.cropFace(from: pixelBuffer, box: firstFace.boundingBox) {
                    self.handleCapturedFace(faceImage)
                }
            }
        }
    }
    
    func startCamera() {
        guard !isCameraRunning else { return }
        isCameraRunning = true
        cameraService.startSession()
    }

    func stopCamera() {
        guard isCameraRunning else { return }
        isCameraRunning = false
        cameraService.stopSession()
    }
    
    
    private func cropFace(from pixelBuffer: CVPixelBuffer, box: CGRect) -> UIImage? {
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        var rect = VNImageRectForNormalizedRect(box, Int(width), Int(height))
        
        let padding: CGFloat = 0.3
        
        let side = max(rect.width, rect.height)
        
        let squareRect = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
        
        rect = squareRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        
        let newWidth = rect.width * (1 + padding)
        let newHeight = rect.height * (1 + padding)
        
        let newX = rect.origin.x - (newWidth - rect.width) / 2
        let newY = rect.origin.y - (newHeight - rect.height) / 2
        
        rect = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        
        let cropped = ciImage.cropped(to: rect)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else { return nil }
        
        return UIImage(
            cgImage: cgImage,
            scale: 1.0,
            orientation: .leftMirrored
        )
    }
    
    func handleCapturedFace(_ image: UIImage) {
        
        guard let embedding = faceRecognitionService.getEmbedding(from: image) else {
            return
        }
        
        let name = faceRecognitionService.recognizeFace(
            embedding,
            from: storageService.savedFaces
        )
        
        processRecognitionResult(name, image: image)
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
    
    private func recognizeFaces() {
        
        guard let pixelBuffer = currentPixelBuffer else { return }
        
        var updatedFaces: [DetectedFace] = []
        
        for face in detectedFaces {
            
            if let cropped = cropFace(from: pixelBuffer, box: face.boundingBox),
               let embedding = faceRecognitionService.getEmbedding(from: cropped) {
                
                let name = faceRecognitionService.recognizeFace(
                    embedding,
                    from: storageService.savedFaces
                )
                
                var updatedFace = face
                updatedFace.name = name
                
                updatedFaces.append(updatedFace)
            }
        }
        
        DispatchQueue.main.async {
            self.detectedFaces = updatedFaces
        }
    }
    
    func processRecognitionResult(_ name: String, image: UIImage) {
        
        // Add to buffer
        recentPredictions.append(name)
        
        if recentPredictions.count > predictionWindow {
            recentPredictions.removeFirst()
        }
        
        // Find most common result
        let stableName = recentPredictions
            .reduce(into: [:]) { counts, name in
                counts[name, default: 0] += 1
            }
            .max(by: { $0.value < $1.value })?.key
        
        guard let finalName = stableName else { return }
        
        let now = Date()
        
        // 🚫 Prevent repeated triggers
        if finalName == lastRecognizedName &&
           now.timeIntervalSince(lastRecognitionTime) < recognitionCooldown {
            return
        }
        
        lastRecognizedName = finalName
        lastRecognitionTime = now
        
        // 🔥 Trigger ONCE
        handleStableRecognition(finalName, image: image)
    }
    
    func handleStableRecognition(_ name: String, image: UIImage) {
        
        DispatchQueue.main.async {
            
            if name == "Unknown" && self.capturedFace == nil {
                
                self.capturedFace = image
                self.showNameInput = true
                
                self.recognizedName = "New Face Detected"
                self.showRecognitionBanner = true
                
                self.speechService.speak("Face not recognized. Please register.")
                
            } else {
                
                self.recognizedName = "\(name) marked present"
                self.showRecognitionBanner = true
                
                self.markAttendance(name: name)
                
                self.speechService.speak("Welcome \(name)")
                
                // Reset after delay (ready for next person)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.showRecognitionBanner = false
                    self.resetRecognitionState()
                }
            }
        }
    }
    
    func resetRecognitionState() {
        recentPredictions.removeAll()
        lastRecognizedName = nil
    }
    
}
