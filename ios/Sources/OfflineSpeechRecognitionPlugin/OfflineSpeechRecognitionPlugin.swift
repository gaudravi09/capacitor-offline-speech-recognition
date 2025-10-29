import Capacitor
import AVFoundation
import Foundation

@objc(OfflineSpeechRecognitionPlugin)
public class OfflineSpeechRecognitionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let jsName = "OfflineSpeechRecognition"
    public let identifier = "OfflineSpeechRecognitionPlugin"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getSupportedLanguages", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDownloadedLanguageModels", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "downloadLanguageModel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startRecognition", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecognition", returnType: CAPPluginReturnPromise)
    ]
    
    private var audioEngine: AVAudioEngine?
    private var processingQueue: DispatchQueue?
    private var voskModel: VoskModel?
    private var voskRecognizer: VoskRecognizer?
    private var isRecording = false
    private var currentLanguage = "en-us"
    private var modelDownloadManager: ModelDownloadManager?
    
    // supported languages mapping to model names - same as Android
    private let supportedLanguages: [String: String] = [
        "en-us": "model-en",
        "de": "model-de",
        "fr": "model-fr",
        "es": "model-es",
        "pt": "model-pt",
        "zh": "model-zh",
        "ru": "model-ru",
        "tr": "model-tr",
        "vi": "model-vi",
        "it": "model-it",
        "hi": "model-hi",
        "gu": "model-gu",
        "te": "model-te",
        "ja": "model-ja",
        "ko": "model-ko"
    ]
    
    // Language names mapping
    private let languageNames: [String: String] = [
        "hi": "Hindi",
        "ko": "Korean",
        "de": "German",
        "fr": "French",
        "te": "Telugu",
        "es": "Spanish",
        "zh": "Chinese",
        "ru": "Russian",
        "tr": "Turkish",
        "it": "Italian",
        "gu": "Gujarati",
        "ja": "Japanese",
        "pt": "Portuguese",
        "vi": "Vietnamese",
        "en-us": "English (US)",
        "en-in": "English (India)"
    ]
    
    override public func load() {
        super.load()
        print("SpeechToTextPlugin loaded")
        requestMicrophonePermission()
        modelDownloadManager = ModelDownloadManager()
        print("Model download manager initialized")
    }
    
    // MARK: - Plugin Methods
    
    @objc func getSupportedLanguages(_ call: CAPPluginCall) {
        var languages: [[String: Any]] = []
        
        for (code, modelName) in supportedLanguages {
            let language: [String: Any] = [
                "code": code,
                "modelName": modelName,
                "name": languageNames[code] ?? code,
                "offlineSupported": true
            ]
            languages.append(language)
        }
        
        call.resolve(["languages": languages])
    }
    
    @objc func getDownloadedLanguageModels(_ call: CAPPluginCall) {
        var models: [[String: Any]] = []
        
        guard let downloadManager = modelDownloadManager else {
            call.reject("Model download manager not initialized")
            return
        }
        
        for (code, modelName) in supportedLanguages {
            if downloadManager.isModelDownloaded(modelName: modelName) {
                let model: [String: Any] = [
                    "modelName": modelName,
                    "language": code,
                    "name": languageNames[code] ?? code,
                    "size": downloadManager.getModelSize(modelName: modelName),
                    "offlineSupported": true
                ]
                models.append(model)
            }
        }
        
        call.resolve(["models": models])
    }
    
    @objc func downloadLanguageModel(_ call: CAPPluginCall) {
        guard let language = call.getString("language") else {
            call.reject("Language parameter is required")
            return
        }
        
        guard let modelName = supportedLanguages[language] else {
            call.reject("Unsupported language: \(language)")
            return
        }
        
        guard let downloadManager = modelDownloadManager else {
            call.reject("Model download manager not initialized")
            return
        }
        
        // Check if model is already downloaded
        if downloadManager.isModelDownloaded(modelName: modelName) {
            call.resolve([
                "success": true,
                "language": language,
                "message": "Model already downloaded",
                "offlineSupported": true
            ])
            return
        }
        
        // Check if download is already in progress
        if downloadManager.isDownloadInProgress(modelName: modelName) {
            call.reject("Download already in progress for this model")
            return
        }
        
        // Start download
        downloadManager.downloadModel(
            modelName: modelName,
            onProgress: { progress in
                let progressData: [String: Any] = [
                    "progress": progress,
                    "message": "Downloading model... \(progress)%"
                ]
                self.notifyListeners("downloadProgress", data: progressData)
            },
            onSuccess: {
                call.resolve([
                    "success": true,
                    "language": language,
                    "message": "Model downloaded successfully",
                    "offlineSupported": true
                ])
            },
            onError: { error in
                call.reject("Error downloading model: \(error)")
            }
        )
    }
    
    @objc func startRecognition(_ call: CAPPluginCall) {
        let language = call.getString("language", "en-us")
        
        print("Starting recognition for language: \(language)")
        
        guard let modelName = supportedLanguages[language] else {
            print("ERROR: Unsupported language: \(language)")
            call.reject("Unsupported language: \(language)")
            return
        }
        
        guard let downloadManager = modelDownloadManager else {
            call.reject("Model download manager not initialized")
            return
        }
        
        // Check if model is downloaded
        if !downloadManager.isModelDownloaded(modelName: modelName) {
            call.reject("Language model not downloaded. Please download the model first.")
            return
        }
        
        // Check permissions
        guard checkMicrophonePermission() else {
            print("ERROR: Microphone permission not granted")
            call.reject("Microphone permission is required")
            return
        }
        
        do {
            try loadModel(modelName: modelName)
            startVoskRecognition(language: language)
            call.resolve()
        } catch {
            print("ERROR: Failed to load model: \(error)")
            call.reject("Failed to load model: \(error.localizedDescription)")
        }
    }
    
    @objc func stopRecognition(_ call: CAPPluginCall) {
        stopVoskRecognition()
        call.resolve()
    }
    
    // MARK: - Private Methods
    
    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Microphone permission granted")
                } else {
                    print("Microphone permission denied")
                }
            }
        }
    }
    
    private func checkMicrophonePermission() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        switch audioSession.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            audioSession.requestRecordPermission { granted in
                // Permission result handled asynchronously
            }
            return false
        @unknown default:
            return false
        }
    }
    
    private func loadModel(modelName: String) throws {
        guard let downloadManager = modelDownloadManager else {
            throw NSError(domain: "SpeechToTextPlugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model download manager not initialized"])
        }
        
        // Resolve the actual root dir (handles zips with a top-level folder)
        let modelDir = downloadManager.getResolvedModelDirectory(modelName: modelName)
        
        if !FileManager.default.fileExists(atPath: modelDir.path) {
            throw NSError(domain: "SpeechToTextPlugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model directory not found: \(modelDir.path)"])
        }
        
        if !downloadManager.verifyModel(modelDir: modelDir) {
            throw NSError(domain: "SpeechToTextPlugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model verification failed. Model files may be corrupted or incomplete."])
        }
        
        print("Loading Vosk model from: \(modelDir.path)")
        
        // Initialize processing queue if not already done
        if processingQueue == nil {
            processingQueue = DispatchQueue(label: "voskRecognizerQueue")
        }
        
        // Load the model
        voskModel = VoskModel(modelPath: modelDir.path)
        
        if voskModel?.model == nil {
            throw NSError(domain: "SpeechToTextPlugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load Vosk model from: \(modelDir.path)"])
        }
        
        print("Vosk model loaded successfully")
    }
    
    private func startVoskRecognition(language: String) {
        guard let voskModel = voskModel else {
            print("ERROR: Vosk model not initialized")
            return
        }
        
        print("Starting Vosk recognition...")
        
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured successfully")
            
            // Create a new audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                print("ERROR: Unable to create audio engine")
                return
            }
            
            let inputNode = audioEngine.inputNode
            let formatInput = inputNode.inputFormat(forBus: 0)
            print("Input format: sampleRate=\(formatInput.sampleRate), channels=\(formatInput.channelCount)")
            
            let formatPcm = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16, 
                                        sampleRate: formatInput.sampleRate, 
                                        channels: 1, 
                                        interleaved: true)
            
            guard let formatPcm = formatPcm else {
                print("ERROR: Unable to create PCM format")
                return
            }
            
            // Create Vosk recognizer
            print("Creating Vosk recognizer with sample rate: \(formatInput.sampleRate)")
            voskRecognizer = VoskRecognizer(model: voskModel, sampleRate: Float(formatInput.sampleRate))
            guard let voskRecognizer = voskRecognizer else {
                print("ERROR: Unable to create Vosk recognizer")
                return
            }
            print("Vosk recognizer created successfully")
            
            inputNode.installTap(onBus: 0,
                                 bufferSize: UInt32(formatInput.sampleRate / 10),
                                 format: formatPcm) { buffer, time in
                                    self.processingQueue?.async {
                                        let result = voskRecognizer.recognizeData(buffer: buffer)
                                        
                                        // Parse JSON result
                                        if let data = result.data(using: .utf8) {
                                            do {
                                                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                                    let text = json["text"] as? String ?? ""
                                                    let partial = json["partial"] as? String ?? ""
                                                    
                                                    DispatchQueue.main.async {
                                                        // Notify listeners with recognition result
                                                        if !text.isEmpty {
                                                            print("Final result: \(text)")
                                                            self.notifyListeners("recognitionResult", data: [
                                                                "text": text,
                                                                "isFinal": true,
                                                                "language": language
                                                            ])
                                                        } else if !partial.isEmpty {
                                                            print("Partial result: \(partial)")
                                                            self.notifyListeners("recognitionResult", data: [
                                                                "text": partial,
                                                                "isFinal": false,
                                                                "language": language
                                                            ])
                                                        }
                                                    }
                                                }
                                            } catch {
                                                print("Error parsing Vosk result: \(error)")
                                            }
                                        }
                                    }
            }
            
            // Start the stream of audio data
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            currentLanguage = language
            print("Audio engine started successfully")
            
        } catch {
            print("ERROR: Unable to start AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    private func stopVoskRecognition() {
        if let audioEngine = audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        voskRecognizer = nil
        isRecording = false
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session deactivation failed: \(error)")
        }
    }
    
    deinit {
        stopVoskRecognition()
    }
}