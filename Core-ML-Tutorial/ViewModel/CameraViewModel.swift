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
    @Published var capturedFace: UIImage?
    @Published var showNameInput: Bool = false
    @Published var attendanceRecords: [AttendanceRecord] = []
    
    struct Person: Codable, Identifiable {
        let id: UUID
        let name: String
        let imagePath: String
    }
    
    struct AttendanceRecord: Identifiable {
        let id = UUID()
        let name: String
        let date: Date
    }
    
    @Published var savedFaces: [Person] = []
    
    private var recentPredictions: [String] = []
    private var lastPredictionTime = Date()
    
    var currentPixelBuffer: CVPixelBuffer?
    
    
    let session = AVCaptureSession()
    
    override init() {
        super.init()
        setupCamera()
        loadSavedFaces()
    }
    
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func getFacesDirectory() -> URL {
        let url = getDocumentsDirectory().appendingPathComponent("faces")
        
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        
        return url
    }
    
    func setupCamera() {
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
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
        self.currentPixelBuffer = pixelBuffer
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
        

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .leftMirrored // match this with UIImage
        )
        
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
    
    func captureFace(from box: CGRect) {
        guard let pixelBuffer = currentPixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        let rect = VNImageRectForNormalizedRect(box, Int(width), Int(height))
        let cropped = ciImage.cropped(to: rect)
        let context = CIContext()
        
        if let cgImage = context.createCGImage(cropped, from: cropped.extent) {
//               let uiImage = UIImage(cgImage: cgImage)
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .leftMirrored)
               
               DispatchQueue.main.async {
                   self.handleCapturedFace(uiImage)
               }
           }
    }
    
    func handleCapturedFace(_ image: UIImage) {
        
        let name = recognizeFace(image)
        
        print("Recognized: \(name)")
        
        if name == "Unknown" {
            // New user → register
            self.capturedFace = image
            self.showNameInput = true
        } else {
            // Known user → mark attendance
            markAttendance(name: name)
        }
    }
    
    func markAttendance(name: String) {
        
        let record = AttendanceRecord(name: name, date: Date())
        attendanceRecords.append(record)
        
        print("Attendance marked for \(name)")
    }
    
    
    func saveFace(name: String) {
        
        guard let face = capturedFace else { return }
        
        let id = UUID()
        let fileName = "\(id).png"
        let fileURL = getFacesDirectory().appendingPathComponent(fileName)
        
        guard let data = face.pngData() else { return }
        
        do {
            try data.write(to: fileURL)
            
            let person = Person(id: id, name: name, imagePath: fileName)
            savedFaces.append(person)
            saveMetadata()
            showNameInput = false
        } catch {
            print("Error saving image: \(error)")
        }
    }
    
    private func saveMetadata() {
        let url = getDocumentsDirectory().appendingPathComponent("faces.json")
        
        do {
            let data = try JSONEncoder().encode(savedFaces)
            try data.write(to: url)
        } catch {
            print("Error saving metadata: \(error)")
        }
    }
    
    func loadSavedFaces() {
        let url = getDocumentsDirectory().appendingPathComponent("faces.json")
        
        guard let data = try? Data(contentsOf: url) else { return }
        
        do {
            savedFaces = try JSONDecoder().decode([Person].self, from: data)
        } catch {
            print("Error loading metadata: \(error)")
        }
    }
    
    func loadImage(for person: Person) -> UIImage? {
        let url = getFacesDirectory().appendingPathComponent(person.imagePath)
        return UIImage(contentsOfFile: url.path)
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
    
    func recognizeFace(_ image: UIImage) -> String {
        
        guard let inputData = image.pngData() else { return "Unknown" }
        
        var bestMatchName = "Unknown"
        var bestScore: Float = 0.0
        
        for person in savedFaces {
            
            guard let savedImage = loadImage(for: person),
                  let savedData = savedImage.pngData() else { continue }
            
            let similarity = compareImages(data1: inputData, data2: savedData)
            
            if similarity > bestScore {
                bestScore = similarity
                bestMatchName = person.name
            }
        }
        
        // 🔥 Threshold to avoid false matches
        return bestScore > 0.1 ? bestMatchName : "Unknown"
    }
    
    func compareImages(data1: Data, data2: Data) -> Float {
        
        let count = min(data1.count, data2.count)
        
        var matchCount = 0
        
        for i in 0..<count {
            if data1[i] == data2[i] {
                matchCount += 1
            }
        }
        
        return Float(matchCount) / Float(count)
    }
    
}
