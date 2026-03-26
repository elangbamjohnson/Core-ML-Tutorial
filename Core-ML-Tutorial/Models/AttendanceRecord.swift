//
//  AttendanceRecord.swift
//  Core ML tutorial
//
//  Created by Johnson on 26/03/26.
//

import Foundation

struct AttendanceRecord: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
}
