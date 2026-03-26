//
//  FaceRecognitionService.swift
//  Core ML tutorial
//
//  Created by Johnson on 26/03/26.
//

import Foundation
import UIKit
import CoreML

class FaceRecognitionService {
    
    private let model: Facenet6
    
    init() {
        do {
            self.model = try Facenet6(configuration: MLModelConfiguration())
        } catch {
            fatalError("❌ Failed to load model: \(error)")
        }
    }
    
    // MARK: - Public API
    
    func recognizeFace(_ image: UIImage, from people: [Person]) -> String {
        
        guard let embedding = getEmbedding(from: image) else {
            return "Unknown"
        }
        
        var bestMatch = "Unknown"
        var bestScore: Float = -1
        
        for person in people {
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
    
    func getEmbedding(from image: UIImage) -> [Float]? {
        
        guard let input = imageToMLMultiArray(image) else { return nil }
        
        do {
            let output = try model.prediction(input: input)
            let embeddingArray = output.embeddings
            
            var embedding = (0..<embeddingArray.count).map {
                Float(truncating: embeddingArray[$0])
            }
            
            // 🔥 Normalize vector (VERY IMPORTANT)
            let norm = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
            embedding = embedding.map { $0 / norm }
            
            return embedding
            
        } catch {
            print("Embedding error:", error)
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        return dotProduct / (normA * normB)
    }
    
    private func imageToMLMultiArray(_ image: UIImage) -> MLMultiArray? {
        
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
}
