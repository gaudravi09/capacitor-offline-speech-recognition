package dev.ravi.offlinespeech;

import org.vosk.Model;
import org.vosk.Recognizer;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONException;

import java.io.File;
import java.util.Map;
import java.util.HashMap;
import java.io.IOException;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

import android.Manifest;
import android.util.Log;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.content.pm.PackageManager;

import androidx.core.app.ActivityCompat;
import androidx.annotation.RequiresPermission;

import com.getcapacitor.Plugin;
import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.PermissionCallback;

@CapacitorPlugin(
    name = "OfflineSpeechRecognition",
    permissions = {
        @Permission(
            strings = {
                Manifest.permission.INTERNET,
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            },
            alias = "audio"
        )
    }
)
public class OfflineSpeechRecognitionPlugin extends Plugin {

    private static final String TAG = "OfflineSpeechRecognitionPlugin";

    private Model currentModel;
    private Recognizer recognizer;
    private AudioRecord audioRecord;
    private boolean isRecording = false;
    private ExecutorService executorService;
    private String currentLanguage = "en-us";
    private ModelDownloadManager modelDownloadManager;

    // supported languages mapping to model names
    private static final Map<String, String> SUPPORTED_LANGUAGES = new HashMap<String, String>() {{
        put("en-us", "model-en");
        put("de", "model-de");
        put("fr", "model-fr");
        put("es", "model-es");
        put("pt", "model-pt");
        put("zh", "model-zh");
        put("ru", "model-ru");
        put("tr", "model-tr");
        put("vi", "model-vi");
        put("it", "model-it");
        put("hi", "model-hi");
        put("gu", "model-gu");
        put("te", "model-te");
        put("ja", "model-ja");
        put("ko", "model-ko");
    }};

    @Override
    public void load() {
        super.load();
        executorService = Executors.newCachedThreadPool();
        modelDownloadManager = new ModelDownloadManager(getContext());
    }

    @PluginMethod()
    public void echo(PluginCall call) {
        String value = call.getString("value");
        call.resolve(new JSObject().put("value", value));
    }

    @PluginMethod()
    public void getSupportedLanguages(PluginCall call) {
        try {
            JSONArray languages = new JSONArray();
            for (Map.Entry<String, String> entry : SUPPORTED_LANGUAGES.entrySet()) {
                JSONObject language = new JSONObject();

                language.put("code", entry.getKey());
                language.put("modelName", entry.getValue());
                language.put("name", getLanguageName(entry.getKey()));

                languages.put(language);
            }

            JSObject result = new JSObject();
            result.put("languages", languages);
            call.resolve(result);
        } catch (JSONException e) {
            Log.e(TAG, "Error creating supported languages response", e);
            call.reject("Error getting supported languages", e);
        }
    }

    @PluginMethod()
    public void getDownloadedLanguageModels(PluginCall call) {
        try {
            JSONArray downloadedModels = new JSONArray();

            // check each supported language to see if model is downloaded
            for (Map.Entry<String, String> entry : SUPPORTED_LANGUAGES.entrySet()) {
                String modelName = entry.getValue();
                String languageCode = entry.getKey();

                if (modelDownloadManager.isModelDownloaded(modelName)) {
                    JSONObject model = new JSONObject();

                    model.put("modelName", modelName);
                    model.put("language", languageCode);
                    model.put("name", getLanguageName(languageCode));
                    model.put("size", modelDownloadManager.getModelSize(modelName));

                    downloadedModels.put(model);
                }
            }

            JSObject result = new JSObject();
            result.put("models", downloadedModels);
            call.resolve(result);
        } catch (JSONException e) {
            Log.e(TAG, "Error getting downloaded models", e);
            call.reject("Error getting downloaded models", e);
        }
    }

    @PluginMethod()
    public void downloadLanguageModel(PluginCall call) {
        String language = call.getString("language");
        if (language == null || !SUPPORTED_LANGUAGES.containsKey(language)) {
            call.reject("Invalid or unsupported language code");
            return;
        }

        String modelName = SUPPORTED_LANGUAGES.get(language);

        // check if model is already downloaded
        if (modelDownloadManager.isModelDownloaded(modelName)) {
            JSObject result = new JSObject();

            result.put("success", true);
            result.put("language", language);
            result.put("message", "Model already downloaded");

            call.resolve(result);
            return;
        }

        // check if download is already in progress
        if (modelDownloadManager.isDownloadInProgress(modelName)) {
            call.reject("Download already in progress for this model");
            return;
        }

        if (!hasAudioPermissions()) {
            requestAudioPermissions(call);
            return;
        }

        // use ModelDownloadManager to download the model
        modelDownloadManager.downloadModel(
            modelName,
            progress -> {
                JSObject progressData = new JSObject();
                progressData.put("progress", progress);
                progressData.put("message", "Downloading model... " + progress + "%");
                notifyListeners("downloadProgress", progressData);
            },
            () -> {
                JSObject result = new JSObject();
                result.put("success", true);
                result.put("language", language);
                result.put("modelName", modelName);
                call.resolve(result);
            },
            error -> call.reject("Error downloading model: " + error)
        );
    }

    @PluginMethod()
    @RequiresPermission(Manifest.permission.RECORD_AUDIO)
    public void startRecognition(PluginCall call) {
        String language = call.getString("language", "en-us");

        if (!hasAudioPermissions()) {
            requestAudioPermissions(call);
            return;
        }

        String modelName = SUPPORTED_LANGUAGES.get(language);
        if (modelName == null) {
            call.reject("Unsupported language: " + language);
            return;
        }

        if (!modelDownloadManager.isModelDownloaded(modelName)) {
            call.reject("Language model not downloaded. Please download the model first.");
            return;
        }

        try {
            loadModel(modelName);
            startAudioRecording();
            call.resolve();
        } catch (Exception e) {
            Log.e(TAG, "Error starting recognition", e);
            call.reject("Error starting recognition: " + e.getMessage());
        }
    }

    @PluginMethod()
    public void stopRecognition(PluginCall call) {
        try {
            stopAudioRecording();
            if (recognizer != null) {
                recognizer.close();
                recognizer = null;
            }
            call.resolve();
        } catch (Exception e) {
            Log.e(TAG, "Error stopping recognition", e);
            call.reject("Error stopping recognition: " + e.getMessage());
        }
    }

    @PermissionCallback
    @RequiresPermission(Manifest.permission.RECORD_AUDIO)
    private void audioPermissionsCallback(PluginCall call) {
        if (hasAudioPermissions()) {
            String method = call.getMethodName();
            switch (method) {
                case "downloadLanguageModel":
                    downloadLanguageModel(call);
                    break;
                case "startRecognition":
                    startRecognition(call);
                    break;
            }
        } else {
            call.reject("Audio permissions are required for speech recognition");
        }
    }

    private boolean hasAudioPermissions() {
        return ActivityCompat.checkSelfPermission(getContext(), Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestAudioPermissions(PluginCall call) {
        requestPermissionForAlias("audio", call, "audioPermissionsCallback");
    }

    private void loadModel(String modelName) throws IOException {
        File modelDir = modelDownloadManager.getModelDirectory(modelName);

        if (!modelDir.exists()) {
            throw new IOException("Model directory not found: " + modelDir.getAbsolutePath());
        }

        if (!modelDownloadManager.verifyModel(modelDir)) {
            throw new IOException("Model verification failed for: " + modelDir.getAbsolutePath() + ". Model files may be corrupted or incomplete.");
        }

        Log.d(TAG, "Loading Vosk model from: " + modelDir.getAbsolutePath());

        try {
            currentModel = new Model(modelDir.getAbsolutePath());
            recognizer = new Recognizer(currentModel, 16000.0f);
            Log.d(TAG, "Vosk model loaded successfully");
        } catch (Exception e) {
            Log.e(TAG, "Failed to load Vosk model from: " + modelDir.getAbsolutePath(), e);
            throw new IOException("Failed to load Vosk model: " + e.getMessage(), e);
        }

        // find the language code for this model name
        for (Map.Entry<String, String> entry : SUPPORTED_LANGUAGES.entrySet()) {
            if (entry.getValue().equals(modelName)) {
                currentLanguage = entry.getKey();
                break;
            }
        }
    }

    @RequiresPermission(Manifest.permission.RECORD_AUDIO)
    private void startAudioRecording() {
        int sampleRate = 16000;
        int channelConfig = AudioFormat.CHANNEL_IN_MONO;
        int audioFormat = AudioFormat.ENCODING_PCM_16BIT;

        int bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat);
        audioRecord = new AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, channelConfig, audioFormat, bufferSize);

        audioRecord.startRecording();
        isRecording = true;

        // start recognition thread
        executorService.execute(this::processAudioData);
    }

    private void stopAudioRecording() {
        isRecording = false;
        if (audioRecord != null) {
            audioRecord.stop();
            audioRecord.release();
            audioRecord = null;
        }
    }

    private void processAudioData() {
        byte[] buffer = new byte[4096];

        while (isRecording && audioRecord != null) {
            int bytesRead = audioRecord.read(buffer, 0, buffer.length);
            if (bytesRead > 0 && recognizer != null) {
                if (recognizer.acceptWaveForm(buffer, bytesRead)) {
                    // final result
                    String result = recognizer.getResult();
                    notifyRecognitionResult(result, true);
                } else {
                    // partial result
                    String partialResult = recognizer.getPartialResult();
                    notifyRecognitionResult(partialResult, false);
                }
            }
        }

        // get final result
        if (recognizer != null) {
            String finalResult = recognizer.getFinalResult();
            notifyRecognitionResult(finalResult, true);
        }
    }

    private void notifyRecognitionResult(String result, boolean isFinal) {
        try {
            JSONObject resultJson = new JSONObject(result);
            String text = resultJson.optString("text", "");

            if (!text.isEmpty()) {
                JSObject recognitionData = new JSObject();
                recognitionData.put("text", text);
                recognitionData.put("isFinal", isFinal);
                recognitionData.put("language", currentLanguage);
                notifyListeners("recognitionResult", recognitionData);
            }
        } catch (JSONException e) {
            Log.e(TAG, "Error parsing recognition result", e);
        }
    }

    private String getLanguageName(String code) {
        Map<String, String> languageNames = new HashMap<String, String>() {{
            put("hi", "Hindi");
            put("ko", "Korean");
            put("de", "German");
            put("fr", "French");
            put("te", "Telugu");
            put("es", "Spanish");
            put("zh", "Chinese");
            put("ru", "Russian");
            put("tr", "Turkish");
            put("it", "Italian");
            put("gu", "Gujarati");
            put("ja", "Japanese");
            put("pt", "Portuguese");
            put("vi", "Vietnamese");
            put("en-us", "English (US)");
            put("en-in", "English (India)");
        }};

        return languageNames.getOrDefault(code, code);
    }

    @Override
    protected void handleOnDestroy() {
        super.handleOnDestroy();

        if (isRecording) {
            stopAudioRecording();
        }

        if (recognizer != null) {
            recognizer.close();
            recognizer = null;
        }

        if (currentModel != null) {
            currentModel.close();
            currentModel = null;
        }

        if (executorService != null) {
            executorService.shutdown();
            executorService = null;
        }
    }
}
