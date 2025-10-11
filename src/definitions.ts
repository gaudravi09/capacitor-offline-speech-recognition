export interface Language {
    code: string;
    name: string;
    modelFile: string;
}

export interface DownloadedModel {
    language: string;
    name: string;
    path: string;
    size: number;
}

export interface DownloadProgress {
    progress: number;
    message: string;
}

export interface RecognitionResult {
    text: string;
    isFinal: boolean;
    language: string;
}

export interface OfflineSpeechRecognitionPlugin {    
    /**
     * Get all supported languages for speech recognition
     */
    getSupportedLanguages(): Promise<{ languages: Language[] }>;
    
    /**
     * Get all downloaded language models on the device
     */
    getDownloadedLanguageModels(): Promise<{ models: DownloadedModel[] }>;
    
    /**
     * Download a language model for offline use
     * @param options - Language code to download
     */
    downloadLanguageModel(options: { language: string }): Promise<{ success: boolean; language: string; modelName?: string; message?: string }>;
    
    /**
     * Start speech recognition
     * @param options - Language code for recognition (defaults to 'en-us')
     */
    startRecognition(options?: { language?: string }): Promise<void>;
    
    /**
     * Stop speech recognition
     */
    stopRecognition(): Promise<void>;
    
    /**
     * Add listener for download progress updates
     */
    addListener(eventName: 'downloadProgress', listenerFunc: (progress: DownloadProgress) => void): Promise<{ remove: () => void }>;
    
    /**
     * Add listener for recognition results
     */
    addListener(eventName: 'recognitionResult', listenerFunc: (result: RecognitionResult) => void): Promise<{ remove: () => void }>;
    
    /**
     * Remove all listeners
     */
    removeAllListeners(): Promise<void>;
}
