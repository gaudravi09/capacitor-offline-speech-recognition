import Foundation
import Network
import SSZipArchive

public class ModelDownloadManager {
    private let cacheDirectory: URL
    private let userDefaults = UserDefaults.standard
    // Retain KVO observations for URLSessionTask progress to avoid deallocation
    private var taskProgressObservations: [URLSessionTask: NSKeyValueObservation] = [:]
    
    // Model URLs mapping - same as Android
    private let modelUrls: [String: String] = [
        "model-tr": "https://alphacephei.com/vosk/models/vosk-model-small-tr-0.3.zip",
        "model-pt": "https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip",
        "model-vi": "https://alphacephei.com/vosk/models/vosk-model-small-vn-0.3.zip",
        "model-es": "https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip",
        "model-fr": "https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip",
        "model-de": "https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip",
        "model-it": "https://alphacephei.com/vosk/models/vosk-model-small-it-0.22.zip",
        "model-ru": "https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip",
        "model-hi": "https://alphacephei.com/vosk/models/vosk-model-small-hi-0.22.zip",
        "model-gu": "https://alphacephei.com/vosk/models/vosk-model-small-gu-0.42.zip",
        "model-te": "https://alphacephei.com/vosk/models/vosk-model-small-te-0.42.zip",
        "model-zh": "https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip",
        "model-ja": "https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip",
        "model-ko": "https://alphacephei.com/vosk/models/vosk-model-small-ko-0.22.zip",
        "model-en": "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
    ]
    
    public init() {
        // Use Documents directory for model storage
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("VoskModels")
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    public func downloadModel(
        modelName: String,
        onProgress: @escaping (Int) -> Void,
        onSuccess: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        // Check internet connectivity
        guard isInternetAvailable() else {
            onError("No internet connection available. Please check your network and try again.")
            return
        }
        
        guard let modelUrl = modelUrls[modelName] else {
            onError("Model URL not found for \(modelName)")
            return
        }
        
        print("Starting download for \(modelName) from \(modelUrl)")
        
        let modelDir = cacheDirectory.appendingPathComponent(modelName)
        
        // Mark as in progress
        markInProgress(modelName: modelName, inProgress: true)
        persistProgress(modelName: modelName, progress: 0)
        
        // Download and extract model
        downloadAndExtractModel(url: modelUrl, targetDir: modelDir, onProgress: onProgress) { success in
            if success {
                // Resolve root (handle zips with a top-level folder)
                let resolvedDir = self.resolveModelRoot(modelDir: modelDir)
                // Verify model integrity
                if self.verifyModel(modelDir: resolvedDir) {
                    print("Model \(modelName) downloaded and verified successfully")
                    self.persistProgress(modelName: modelName, progress: 100)
                    self.markInProgress(modelName: modelName, inProgress: false)
                    onSuccess()
                } else {
                    self.markInProgress(modelName: modelName, inProgress: false)
                    onError("Model verification failed - required files missing")
                }
            } else {
                self.markInProgress(modelName: modelName, inProgress: false)
                onError("Download failed")
            }
        }
    }
    
    private func downloadAndExtractModel(
        url: String,
        targetDir: URL,
        onProgress: @escaping (Int) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        guard let downloadUrl = URL(string: url) else {
            completion(false)
            return
        }
        
        var task: URLSessionDownloadTask?
        task = URLSession.shared.downloadTask(with: downloadUrl) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            if let error = error {
                print("Download error: \(error)")
                if let t = task { self.taskProgressObservations.removeValue(forKey: t) }
                completion(false)
                return
            }
            
            guard let tempURL = tempURL else {
                if let t = task { self.taskProgressObservations.removeValue(forKey: t) }
                completion(false)
                return
            }
            
            // Create target directory
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            
            // Extract ZIP file
            do {
                try self.extractZipFile(zipURL: tempURL, targetDir: targetDir)
                // Ensure progress reaches 100 after extraction
                DispatchQueue.main.async { onProgress(100) }
                if let t = task { self.taskProgressObservations.removeValue(forKey: t) }
                completion(true)
            } catch {
                print("Extraction error: \(error)")
                if let t = task { self.taskProgressObservations.removeValue(forKey: t) }
                completion(false)
            }
        }
        
        // Monitor download progress
        guard let createdTask = task else { return }
        let observation = createdTask.progress.observe(\.fractionCompleted) { progress, _ in
            let progressPercent = Int(progress.fractionCompleted * 100)
            DispatchQueue.main.async {
                onProgress(progressPercent)
            }
        }
        // Retain observation for the lifetime of the task
        taskProgressObservations[createdTask] = observation
        
        createdTask.resume()
    }
    
    private func extractZipFile(zipURL: URL, targetDir: URL) throws {
        // Use the simplest overload to avoid signature ambiguity
        let success = SSZipArchive.unzipFile(atPath: zipURL.path, toDestination: targetDir.path)
        if !success {
            throw NSError(domain: "ModelDownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract ZIP file"])
        }
    }
    
    public func isModelDownloaded(modelName: String) -> Bool {
        let modelDir = cacheDirectory.appendingPathComponent(modelName)
        let resolved = resolveModelRoot(modelDir: modelDir)
        return verifyModel(modelDir: resolved)
    }
    
    public func getModelDirectory(modelName: String) -> URL {
        return cacheDirectory.appendingPathComponent(modelName)
    }

    public func getResolvedModelDirectory(modelName: String) -> URL {
        return resolveModelRoot(modelDir: getModelDirectory(modelName: modelName))
    }
    
    public func verifyModel(modelDir: URL) -> Bool {
        print("Verifying model at: \(modelDir.path)")
        
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            print("Model directory does not exist")
            return false
        }
        
        // Check for common Vosk model files
        let commonModelFiles = [
            "uuid",
            "HCLr.fst",
            "am/final.mdl",
            "graph/HCLG.fst",
            "graph/HCLr.fst",
            "conf/model.conf",
            "ivector/final.ie",
            "conf/ivector_extractor.conf",
            "graph/phones/word_boundary.int"
        ]
        
        // Check expected paths relative to this root
        var foundFiles = 0
        for file in commonModelFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                foundFiles += 1
            }
        }
        
        let isValid = foundFiles >= 2
        print("Model verification result: \(isValid) (found \(foundFiles) model files)")
        
        return isValid
    }

    // Resolve actual model root if zip extracted into a nested top-level directory
    private func resolveModelRoot(modelDir: URL) -> URL {
        // If directory already contains expected structure, return as-is
        let confPath = modelDir.appendingPathComponent("conf/model.conf").path
        if FileManager.default.fileExists(atPath: confPath) {
            return modelDir
        }
        // If there's exactly one subdirectory (common in zips), use it
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            let subdirs = contents.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            if subdirs.count == 1 {
                let candidate = subdirs[0]
                // If the candidate contains expected files, use it
                let candidateConf = candidate.appendingPathComponent("conf/model.conf").path
                if FileManager.default.fileExists(atPath: candidateConf) {
                    return candidate
                }
            }
        }
        return modelDir
    }
    
    private func isInternetAvailable() -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        var isConnected = false
        
        monitor.pathUpdateHandler = { path in
            isConnected = path.status == .satisfied
        }
        
        monitor.start(queue: queue)
        
        // Wait a bit for the check to complete
        Thread.sleep(forTimeInterval: 0.1)
        monitor.cancel()
        
        return isConnected
    }
    
    private func markInProgress(modelName: String, inProgress: Bool) {
        if inProgress {
            userDefaults.set(true, forKey: "download_in_progress_\(modelName)")
        } else {
            userDefaults.removeObject(forKey: "download_in_progress_\(modelName)")
            userDefaults.removeObject(forKey: "download_progress_\(modelName)")
        }
    }
    
    private func persistProgress(modelName: String, progress: Int) {
        userDefaults.set(progress, forKey: "download_progress_\(modelName)")
    }
    
    public func isDownloadInProgress(modelName: String) -> Bool {
        return userDefaults.bool(forKey: "download_in_progress_\(modelName)")
    }
    
    public func getModelSize(modelName: String) -> Int64 {
        let modelDir = cacheDirectory.appendingPathComponent(modelName)
        guard FileManager.default.fileExists(atPath: modelDir.path) else { return 0 }
        
        var totalSize: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: modelDir, includingPropertiesForKeys: [.fileSizeKey])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            } catch {
                continue
            }
        }
        
        return totalSize
    }
}
