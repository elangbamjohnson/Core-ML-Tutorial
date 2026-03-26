//
//  SpeechService.swift
//  Core ML tutorial
//
//  Created by Johnson on 26/03/26.
//

import Foundation
import AVFoundation

class SpeechService {
    
    private let synthesizer = AVSpeechSynthesizer()
    
    private var lastSpokenText: String?
    private var lastSpokenTime = Date()
    private let speechInterval: TimeInterval = 2.0
    
    
    func speak(_ text: String) {
        
        let now = Date()
        
        // 🔥 Prevent repeating same speech too quickly
        if text == lastSpokenText &&
           now.timeIntervalSince(lastSpokenTime) < speechInterval {
            return
        }
        
        lastSpokenText = text
        lastSpokenTime = now
        
        // 🔥 Stop current speech safely
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        
        synthesizer.speak(utterance)
    }
    
    
    func reset() {
        lastSpokenText = nil
    }
}
