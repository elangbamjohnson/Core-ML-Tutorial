//
//  ContentView.swift
//  Core ML tutorial
//
//  Created by Johnson Elangbam on 3/20/26.
//

import SwiftUI
import PhotosUI
import Vision

struct ContentView: View {
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isCameraMode = false
    @State private var name: String = ""
    
    @StateObject private var viewModel = ImageClassifierViewModel()
    @StateObject private var cameraVM = CameraViewModel()
    
    var body: some View {
        
        VStack {
            
            // 🔄 Toggle
            Button(isCameraMode ? "Switch to Image Mode" : "Switch to Camera Mode") {
                isCameraMode.toggle()
            }
            .padding()
            
            if isCameraMode {
                
                GeometryReader { geometry in
                    
                    ZStack {
                        
                        // 📷 Camera Preview
                        CameraView(session: cameraVM.cameraSession)
                            .ignoresSafeArea()
                        
                        // 🟩 Face Boxes + Names
                        ForEach(cameraVM.detectedFaces) { face in
                            
                            let rect = VNImageRectForNormalizedRect(
                                face.boundingBox,
                                Int(geometry.size.width),
                                Int(geometry.size.height)
                            )
                            
                            let correctedRect = CGRect(
                                x: rect.origin.x,
                                y: geometry.size.height - rect.origin.y - rect.height,
                                width: rect.width,
                                height: rect.height
                            )
                            
                            ZStack(alignment: .topLeading) {
                                
                                Rectangle()
                                    .stroke(Color.green, lineWidth: 2)
                                
                                Text(face.name)
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                    .offset(x: 4, y: 4)
                            }
                            .frame(width: correctedRect.width, height: correctedRect.height)
                            .position(x: correctedRect.midX, y: correctedRect.midY)
                        }
                        
                        // 🔥 Banner
                        if cameraVM.showRecognitionBanner {
                            VStack {
                                Text(cameraVM.recognizedName)
                                    .font(.headline)
                                    .padding()
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                
                                Spacer()
                            }
                            .padding(.top, 50)
                        }
                    }
                }
                .onAppear {
                    cameraVM.startCamera()   // ✅ start when UI appears
                }
                .onDisappear {
                    cameraVM.stopCamera()    // ✅ stop when leaving
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
        
        // 🔥 GLOBAL MODE SWITCH CONTROL (IMPORTANT)
        .onChange(of: isCameraMode) { isCamera in
            if isCamera {
                cameraVM.startCamera()
            } else {
                cameraVM.stopCamera()
            }
        }
        
        // 🧾 Registration Sheet
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
                    
                    Button("Cancel") {
                        cameraVM.cancelFaceRegistration()
                        name = ""
                    }
                    .foregroundColor(.red)
                    
                    Spacer()
                    
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
        
        .sheet(isPresented: $cameraVM.showResultSheet) {
            
            VStack(spacing: 20) {
                
                Text("Attendance Marked")
                    .font(.title2)
                    .bold()
                
                if let person = cameraVM.recognizedPerson,
                   let image = cameraVM.getImage(for: person) {
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                }
                
                Text(cameraVM.recognizedPerson?.name ?? "")
                    .font(.title)
                
                Text("Marked Present ✅")
                    .foregroundColor(.green)
                
                Button("OK") {
                    cameraVM.dismissResult()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 20)
            }
            .padding()
        }
    }
    
    // MARK: - Image Mode
    
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
