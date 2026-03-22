//
//  ContentView.swift
//  Core ML tutorial
//
//  Created by Johnson Elangbam on 3/20/26.
//

import SwiftUI
import PhotosUI
import Vision
import CoreML

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isCameraMode = false
    
    @StateObject private var viewModel = ImageClassifierViewModel()
    @StateObject private var cameraVM = CameraViewModel()
    
    
    var body: some View {
        
        VStack {
            // Toggle Button
            Button(isCameraMode ? "Switch to Image Mode" : "Switch to Camera Mode") {
                isCameraMode.toggle()
            }
            .padding()
            
            if isCameraMode {
                
                // 🔥 CAMERA UI (YOUR ZSTACK GOES HERE)
                ZStack {
                    CameraView(session: cameraVM.session)
                        .ignoresSafeArea()
                    
                    Text(cameraVM.result)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
            } else {
                VStack(spacing: 20) {
                    
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 300)
                    }
                    
                    if viewModel.isLoading {
                        ProgressView("Analyzing image...")
                    }
                    
                    ForEach(viewModel.results, id: \.self) { result in
                        Text(result)
                            .font(.headline)
                    }
                    
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images
                    ) {
                        Text("Pick Image")
                    }
                }
                .onChange(of: selectedItem) { newItem in
                    loadImage(from: newItem)
                }
            }
        }
    }
    
        
        
        func loadImage(from item: PhotosPickerItem?) {
            guard let item else { return }
            
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    
                    await MainActor.run {
                        self.selectedImage = uiImage
                        viewModel.classifyImage(uiImage)
                    }
                }
            }
        }
    }


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
