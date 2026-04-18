//
//  ImageClassifierViewModel.swift
//  Smart Attendance System
//
//  Created by Johnson Elangbam on 3/21/26.
//

import Foundation
import UIKit
import Vision
import CoreML

class ImageClassifierViewModel: ObservableObject {
    
    @Published var results: [String] = []
    @Published var isLoading: Bool = false
    
    func classifyImage(_ image: UIImage) {
        
        isLoading = true
        results = []
        
        guard let ciImage = CIImage(image: image) else {
            self.results = ["Invalid image"]
            self.isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let config = MLModelConfiguration()
                let coreMLModel = try MobileNetV2(configuration: config)
                let visionModel = try VNCoreMLModel(for: coreMLModel.model)
                
                let request = VNCoreMLRequest(model: visionModel) { request, error in
                    
                    guard let observations = request.results as? [VNClassificationObservation] else {
                        DispatchQueue.main.async {
                            self.results = ["No results"]
                            self.isLoading = false
                        }
                        return
                    }
                    
                    // 🔥 1. Confidence filtering
                    let filtered = observations.filter { $0.confidence > 0.4 }
                    
                    // 🔥 2. Take top 3 after filtering
                    let topResults = filtered.prefix(3)
                    
                    let formattedResults = topResults.map {
                        "Looks like: \($0.identifier) (\(String(format: "%.2f", $0.confidence * 100))%)"
                    }
                    
                    DispatchQueue.main.async {
                        // 🔥 3. Handle empty case
                        if formattedResults.isEmpty {
                            self.results = ["Not confident enough 🤔"]
                        } else {
                            self.results = formattedResults
                        }
                        self.isLoading = false
                    }
                }
                
                // 🔥 4. Better preprocessing
                request.imageCropAndScaleOption = .centerCrop
                
                let handler = VNImageRequestHandler(ciImage: ciImage)
                try handler.perform([request])
                
            } catch {
                DispatchQueue.main.async {
                    self.results = ["Error: \(error.localizedDescription)"]
                    self.isLoading = false
                }
            }
        }
    }
}
