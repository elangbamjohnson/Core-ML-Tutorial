//
//  AttendanceRecord.swift
//  Smart Attendance System
//
//  Created by Johnson on 26/03/26.
//

import Foundation

struct AttendanceRecord: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
}
