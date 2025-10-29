//
//  VoskModel.swift
//  SpeechToTextPlugin
//
//  Created by Vosk Integration
//  Copyright © 2024. All rights reserved.
//

import Foundation

public final class VoskModel {
    
    var model : OpaquePointer!
    var spkModel : OpaquePointer!
    
    init(modelPath: String) {
        // Set to -1 to disable logs
        vosk_set_log_level(0);
        
        print("Loading Vosk model from: \(modelPath)")
        
        // Check if model path exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelPath) else {
            print("ERROR: Model path does not exist: \(modelPath)")
            return
        }
        
        print("Model path exists: \(fileManager.fileExists(atPath: modelPath))")
        
        if fileManager.fileExists(atPath: modelPath) {
            print("Model directory contents:")
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: modelPath)
                for item in contents {
                    print("  - \(item)")
                }
            } catch {
                print("Error listing model directory: \(error)")
            }
        }
        
        model = vosk_model_new(modelPath)
        
        if model == nil {
            print("ERROR: Failed to load Vosk model from \(modelPath)")
        } else {
            print("SUCCESS: Vosk model loaded")
        }
        
        // Try to load speaker model from the same directory
        let spkModelPath = modelPath + "/vosk-model-spk-0.4"
        if fileManager.fileExists(atPath: spkModelPath) {
            spkModel = vosk_spk_model_new(spkModelPath)
            if spkModel == nil {
                print("ERROR: Failed to load Vosk speaker model from \(spkModelPath)")
            } else {
                print("SUCCESS: Vosk speaker model loaded")
            }
        } else {
            print("Speaker model not found at \(spkModelPath), continuing without speaker identification")
        }
    }
    
    deinit {
        if model != nil {
            vosk_model_free(model)
        }
        if spkModel != nil {
            vosk_spk_model_free(spkModel)
        }
    }
    
}
