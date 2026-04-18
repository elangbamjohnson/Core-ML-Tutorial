//
//  Person.swift
//  Smart Attendance System
//
//  Created by Johnson on 26/03/26.
//

import Foundation

struct Person: Codable, Identifiable {
    let id: UUID
    let name: String
    let embedding: [Float]
    let imagePath: String
}
