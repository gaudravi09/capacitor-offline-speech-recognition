import Foundation
import Network
import SSZipArchive

public class ModelDownloadManager {
    private let cacheDirectory: URL
    private let userDefaults = UserDefaults.standard
    // Retain KVO observations for URLSessionTask progress to avoid deallocation
    private var taskProgressObservations: [URLSessionTask: NSKeyValueObservation] = [:]
    private let sessionIdentifier = UUID().uuidString
    
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

        // Clean up any previous partial downloads before starting fresh
        cleanupModelDirectory(modelName: modelName)
        
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
        
        let signatures = collectModelFileSignatures(at: modelDir)
        if signatures.isEmpty {
            print("Model directory has no files")
            return false
        }
        
        let evaluation = evaluateModelSignatures(signatures)
        print("Model verification result: \(evaluation.isValid) (found \(evaluation.matchedFiles.count) key files)")
        if !evaluation.matchedFiles.isEmpty {
            print("Matched key files: \(evaluation.matchedFiles.sorted())")
        }
        if !evaluation.isValid {
            let sample = Array(signatures.prefix(10))
            print("Sample files for troubleshooting: \(sample)")
        }
        return evaluation.isValid
    }

    // Resolve actual model root if zip extracted into a nested top-level directory
    private func resolveModelRoot(modelDir: URL) -> URL {
        // If directory already contains expected structure, return as-is
        if containsModelStructure(at: modelDir) {
            return modelDir
        }
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for url in contents {
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues?.isDirectory == true else { continue }
                if containsModelStructure(at: url) {
                    return url
                }
            }
        }
        if let enumerator = fileManager.enumerator(at: modelDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues?.isDirectory == true else { continue }
                if containsModelStructure(at: url) {
                    return url
                }
            }
        }
        return modelDir
    }

    private func containsModelStructure(at url: URL) -> Bool {
        let signatures = collectModelFileSignatures(at: url)
        return evaluateModelSignatures(signatures).isValid
    }

    private func collectModelFileSignatures(at url: URL) -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var signatures: Set<String> = []
        let basePath = url.path.hasSuffix("/") ? url.path : url.path + "/"
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                let fullPath = fileURL.path
                guard fullPath.hasPrefix(basePath) else { continue }
                let relativePath = String(fullPath.dropFirst(basePath.count))
                if !relativePath.isEmpty {
                    signatures.insert(relativePath.replacingOccurrences(of: "\\", with: "/").lowercased())
                }
            }
        }
        return signatures
    }

    private func evaluateModelSignatures(_ signatures: Set<String>) -> (isValid: Bool, matchedFiles: Set<String>) {
        guard !signatures.isEmpty else { return (false, []) }
        
        var matchedFiles: Set<String> = []
        
        let hasAcoustic = matches(suffixes: ["am/final.mdl", "final.mdl"], in: signatures, matched: &matchedFiles)
        let hasGraph = matches(suffixes: ["graph/hclg.fst", "hclg.fst", "gr.fst"], in: signatures, matched: &matchedFiles)
        let hasConfig = matches(suffixes: ["conf/model.conf", "conf/mfcc.conf", "mfcc.conf"], in: signatures, matched: &matchedFiles)
        let hasIvector = matches(suffixes: ["ivector/final.ie", "ivector/final.dubm", "ivector/final.mat"], in: signatures, matched: &matchedFiles)
        let hasPhones = matches(suffixes: ["graph/phones/word_boundary.int", "word_boundary.int", "phones.txt"], in: signatures, matched: &matchedFiles)
        let hasDisambig = matches(suffixes: ["disambig_tid.int"], in: signatures, matched: &matchedFiles)
        
        var supportingCount = 0
        for flag in [hasGraph, hasConfig, hasIvector, hasPhones, hasDisambig] where flag {
            supportingCount += 1
        }
        
        let isValid = hasAcoustic && supportingCount >= 2
        return (isValid, matchedFiles)
    }

    private func matches(suffixes: [String], in signatures: Set<String>, matched: inout Set<String>) -> Bool {
        for suffix in suffixes {
            if let match = signatures.first(where: { $0.hasSuffix(suffix) }) {
                matched.insert(match)
                return true
            }
        }
        return false
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
        let inProgressKey = makeInProgressKey(modelName: modelName)
        let sessionKey = makeSessionKey(modelName: modelName)
        if inProgress {
            userDefaults.set(true, forKey: inProgressKey)
            userDefaults.set(sessionIdentifier, forKey: sessionKey)
        } else {
            userDefaults.removeObject(forKey: inProgressKey)
            userDefaults.removeObject(forKey: sessionKey)
            userDefaults.removeObject(forKey: "download_progress_\(modelName)")
        }
    }
    
    private func persistProgress(modelName: String, progress: Int) {
        userDefaults.set(progress, forKey: "download_progress_\(modelName)")
    }

    private func makeInProgressKey(modelName: String) -> String {
        return "download_in_progress_\(modelName)"
    }

    private func makeSessionKey(modelName: String) -> String {
        return "download_session_\(modelName)"
    }

    private func cleanupModelDirectory(modelName: String) {
        let modelDir = cacheDirectory.appendingPathComponent(modelName)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            do {
                try FileManager.default.removeItem(at: modelDir)
                print("Cleaned up cached data for \(modelName)")
            } catch {
                print("Warning: Failed to remove cached model directory for \(modelName): \(error)")
            }
        }
    }
    
    public func isDownloadInProgress(modelName: String) -> Bool {
        let inProgressKey = makeInProgressKey(modelName: modelName)
        guard userDefaults.bool(forKey: inProgressKey) else {
            return false
        }

        let sessionKey = makeSessionKey(modelName: modelName)
        guard let storedSession = userDefaults.string(forKey: sessionKey),
              storedSession == sessionIdentifier else {
            print("Detected stale download session for \(modelName). Cleaning up cached data.")
            cleanupModelDirectory(modelName: modelName)
            markInProgress(modelName: modelName, inProgress: false)
            return false
        }

        return true
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
