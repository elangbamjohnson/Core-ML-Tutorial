//
//  SorageService.swift
//  Core ML tutorial
//
//  Created by Johnson on 26/03/26.
//

import Foundation
import UIKit

class StorageService: ObservableObject {
    
    @Published private(set) var savedFaces: [Person] = [] {
        didSet {
            persistMetadata()
        }
    }
    
    // MARK: - Init
    
    init() {
        loadSavedFaces()
    }
    
    // MARK: - Public API
    
    func saveFace(name: String, image: UIImage, embedding: [Float]) -> Person {
        
        let id = UUID()
        let fileName = "\(id).png"
        let fileURL = getFacesDirectory().appendingPathComponent(fileName)
        
        let data = image.pngData()
        try? data?.write(to: fileURL)
        
        let person = Person(
            id: id,
            name: name,
            embedding: embedding,
            imagePath: fileName
        )
        
        savedFaces.append(person)
        persistMetadata()
        return person
    }
    
    
    func loadSavedFaces() {
        let url = getMetadataURL()
        
        guard let data = try? Data(contentsOf: url) else { return }
        
        do {
            savedFaces = try JSONDecoder().decode([Person].self, from: data)
        } catch {
            print("Error loading metadata:", error)
        }
    }
    
    func loadImage(for person: Person) -> UIImage? {
        let url = getFacesDirectory().appendingPathComponent(person.imagePath)
        return UIImage(contentsOfFile: url.path)
    }
    
    // MARK: - Private Helpers
    
    private func persistMetadata() {
        let url = getMetadataURL()
        
        do {
            let data = try JSONEncoder().encode(savedFaces)
            try data.write(to: url)
        } catch {
            print("Error saving metadata:", error)
        }
    }
    
    private func saveImage(_ image: UIImage, id: UUID) -> String? {
        let fileName = "\(id).png"
        let url = getFacesDirectory().appendingPathComponent(fileName)
        
        guard let data = image.pngData() else { return nil }
        
        do {
            try data.write(to: url)
            return fileName
        } catch {
            print("Error saving image:", error)
            return nil
        }
    }
    
    private func getMetadataURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("faces.json")
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
}
