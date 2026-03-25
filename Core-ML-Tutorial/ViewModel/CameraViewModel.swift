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
    @Published var recognizedName: String = ""
    @Published var showRecognitionBanner: Bool = false
    
    
    struct Person: Codable, Identifiable {
        let id: UUID
        let name: String
        let embedding: [Float]
        let imagePath: String   // ✅ bring this back
    }
    
    struct AttendanceRecord: Identifiable {
        let id = UUID()
        let name: String
        let date: Date
    }
    
    @Published var savedFaces: [Person] = []
    
    private var recentPredictions: [String] = []
    private var lastPredictionTime = Date()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenText: String?
    private var lastSpokenTime = Date()
    private let speechInterval: TimeInterval = 2.0
    
    
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
        
        DispatchQueue.main.async {
            if name == "Unknown" {
                // ❌ New user
                self.capturedFace = image
                self.showNameInput = true
                
                self.recognizedName = "New Face Detected"
                self.showRecognitionBanner = true
                
                // 🔥 Voice feedback
                self.speak("Face not recognized. Please register.")
                
            } else {
                // ✅ Known user
                self.recognizedName = "\(name) marked present"
                self.showRecognitionBanner = true
                
                self.markAttendance(name: name)
                
                // 🔥 Voice feedback
                self.speak("Welcome \(name)")
                
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
              let embedding = getEmbedding(from: face) else { return }
        
        let id = UUID()
        let fileName = "\(id).png"
        let fileURL = getFacesDirectory().appendingPathComponent(fileName)
        
        guard let data = face.pngData() else { return }
        
        do {
            try data.write(to: fileURL)
            
            let person = Person(
                id: id,
                name: name,
                embedding: embedding,
                imagePath: fileName   // ✅ now valid again
            )
            
            savedFaces.append(person)
            saveMetadata()
            
            showNameInput = false
            
        } catch {
            print("Error saving image:", error)
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
        
        guard let embedding = getEmbedding(from: image) else {
            return "Unknown"
        }
        
        var bestMatch = "Unknown"
        var bestScore: Float = -1   // cosine can be negative
        
        for person in savedFaces {
            let score = cosineSimilarity(embedding, person.embedding)
            
            print("Comparing with \(person.name), score: \(score)")
            
            if score > bestScore {
                bestScore = score
                bestMatch = person.name
            }
        }
        
        print("Best score:", bestScore)
        
        return bestScore > 0.6 ? bestMatch : "Unknown"
    }
    
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        return dotProduct / (normA * normB)
    }
    
    func imageToMLMultiArray(_ image: UIImage) -> MLMultiArray? {
        
        let size = CGSize(width: 160, height: 160)
        
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = resizedImage?.cgImage else { return nil }
        
        guard let array = try? MLMultiArray(shape: [1, 160, 160, 3], dataType: .float32) else {
            return nil
        }
        
        let context = CGContext(
            data: nil,
            width: 160,
            height: 160,
            bitsPerComponent: 8,
            bytesPerRow: 160 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: 160, height: 160))
        
        guard let pixelData = context?.data else { return nil }
        
        let pointer = pixelData.bindMemory(to: UInt8.self, capacity: 160 * 160 * 4)
        
        var index = 0
        
        for y in 0..<160 {
            for x in 0..<160 {
                
                let offset = (y * 160 + x) * 4
                
                let r = Float(pointer[offset]) / 255.0
                let g = Float(pointer[offset + 1]) / 255.0
                let b = Float(pointer[offset + 2]) / 255.0
                
                array[index] = NSNumber(value: r)
                array[index + 1] = NSNumber(value: g)
                array[index + 2] = NSNumber(value: b)
                
                index += 3
            }
        }
        
        return array
    }
    
    func getEmbedding(from image: UIImage) -> [Float]? {
        
        guard let input = imageToMLMultiArray(image) else { return nil }
        
        do {
            let model = try Facenet6(configuration: MLModelConfiguration())
            let output = try model.prediction(input: input)
            
            let embeddingArray = output.embeddings
            
            var embedding = (0..<embeddingArray.count).map {
                Float(truncating: embeddingArray[$0])
            }
            
            // 🔥 NORMALIZE VECTOR
            let norm = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
            embedding = embedding.map { $0 / norm }
            
            print("Embedding size:", embedding.count)
            
            return embedding
            
        } catch {
            print("Embedding error: \(error)")
            return nil
        }
    }
    
    func speak(_ text: String) {
        
        let now = Date()
        
        // 🔥 Prevent same text repetition
        if text == lastSpokenText &&
           now.timeIntervalSince(lastSpokenTime) < speechInterval {
            return
        }
        
        lastSpokenText = text
        lastSpokenTime = now
        
        // 🔥 Stop current speech safely
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        
        speechSynthesizer.speak(utterance)
    }
    
}
