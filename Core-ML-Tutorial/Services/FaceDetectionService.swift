//
//  FaceDetectionService.swift
//  Core ML tutorial
//
//  Created by Johnson on 26/03/26.
//

import Foundation
import Vision
import CoreVideo

class FaceDetectionService {
    
    func detectFaces(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping ([VNFaceObservation]) -> Void
    ) {
        
        let request = VNDetectFaceRectanglesRequest { request, error in
            
            guard let observations = request.results as? [VNFaceObservation] else {
                completion([])
                return
            }
            
            completion(observations)
        }
        
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .leftMirrored // keep consistent with your camera
        )
        
        do {
            try handler.perform([request])
        } catch {
            print("Face detection error:", error)
            completion([])
        }
    }
}
