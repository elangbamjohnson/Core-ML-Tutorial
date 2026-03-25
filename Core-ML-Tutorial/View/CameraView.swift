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
       
        if let connection = previewLayer.connection {
//            connection.isVideoMirrored = true
            if let connection = previewLayer.connection {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false // 🔥 disable auto
                    connection.isVideoMirrored = true                     // 🔥 then set manually
                }
            }
        }
        
        view.layer.addSublayer(previewLayer)
        
        // 🔥 CRITICAL FIX
        previewLayer.isGeometryFlipped = false
        
        // 🔥 Ensure camera does NOT block touches
        view.isUserInteractionEnabled = false
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
