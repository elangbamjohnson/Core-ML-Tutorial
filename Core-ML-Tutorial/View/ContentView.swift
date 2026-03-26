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
    @State private var name: String = ""
    
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
                    if cameraVM.showRecognitionBanner {
                        VStack {
                            Text(cameraVM.recognizedName)
                                .font(.headline)
                                .padding()
                                .background(Color.green.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .padding()
                            
                            Spacer()
                        }
                    }
                    
                    CameraView(session: cameraVM.cameraSession)
                        .ignoresSafeArea()
                    
                    GeometryReader { geometry in
                        
                        ZStack {
                            ForEach(cameraVM.faceBoxes, id: \.self) { box in
                                
                                let rect = VNImageRectForNormalizedRect(
                                    box,
                                    Int(geometry.size.width),
                                    Int(geometry.size.height)
                                )
                                
                                let correctedRect = CGRect(
                                    x: rect.origin.x,
                                    y: geometry.size.height - rect.origin.y - rect.height,
                                    width: rect.width,
                                    height: rect.height
                                )
                                
                                Rectangle()
                                    .stroke(Color.green, lineWidth: 3)
                                    .frame(width: correctedRect.width, height: correctedRect.height)
                                    .position(x: correctedRect.midX, y: correctedRect.midY)
                            }
                        }
                        // 🔥 TAP GESTURE HERE (NOT on rectangle)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let location = value.location
                                    
                                    print("Tapped at: \(location)")
                                    cameraVM.handleTap(at: location, in: geometry.size)
                                }
                        )
                    }
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
        .sheet(isPresented: $cameraVM.showNameInput) {
            VStack(spacing: 20) {
                
                Text("New Person Detected")
                    .font(.headline)
                
                if let face = cameraVM.capturedFace {
                    Image(uiImage: face)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                }
                
                TextField("Enter name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                HStack {
                    
                    // ❌ Cancel Button
                    Button("Cancel") {
                        cameraVM.cancelFaceRegistration()
                        name = ""
                    }
                    .foregroundColor(.red)
                    
                    Spacer()
                    
                    // ✅ Save Button
                    Button("Save") {
                        cameraVM.saveFace(name: name)
                        name = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
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

func fixOrientation(_ image: UIImage) -> UIImage {
    if image.imageOrientation == .up {
        return image
    }
    
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    image.draw(in: CGRect(origin: .zero, size: image.size))
    let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    return normalizedImage
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
