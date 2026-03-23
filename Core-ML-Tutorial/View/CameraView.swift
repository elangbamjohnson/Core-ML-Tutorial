//
//  CameraView.swift
//  Core ML tutorial
//
//  Created by Johnson Elangbam on 3/22/26.
//

import Foundation
import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
   
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.frame = UIScreen.main.bounds
        
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
