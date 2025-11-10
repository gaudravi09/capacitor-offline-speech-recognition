package dev.ravi.offlinespeech;

import android.util.Log;
import android.os.Looper;
import android.os.Handler;
import android.content.Context;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.content.SharedPreferences;

import java.io.*;
import java.net.URI;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.List;
import java.util.Locale;
import java.util.HashMap;
import java.util.HashSet;
import java.util.ArrayList;
import java.util.zip.ZipEntry;
import java.net.HttpURLConnection;
import java.util.zip.ZipInputStream;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

public class ModelDownloadManager {

    private static final String TAG = "ModelDownloadManager";

    private final Context context;
    private final SharedPreferences prefs;
    private final String sessionId = UUID.randomUUID().toString();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService downloadExecutor = Executors.newSingleThreadExecutor();

    // model URLs mapping - these are the direct download links from alphacephei.com
    private final Map<String, String> modelUrls = new HashMap<String, String>() {{
        put("model-tr", "https://alphacephei.com/vosk/models/vosk-model-small-tr-0.3.zip");
        put("model-pt", "https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip");
        put("model-vi", "https://alphacephei.com/vosk/models/vosk-model-small-vn-0.3.zip");
        put("model-es", "https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip");
        put("model-fr", "https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip");
        put("model-de", "https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip");
        put("model-it", "https://alphacephei.com/vosk/models/vosk-model-small-it-0.22.zip");
        put("model-ru", "https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip");
        put("model-hi", "https://alphacephei.com/vosk/models/vosk-model-small-hi-0.22.zip");
        put("model-gu", "https://alphacephei.com/vosk/models/vosk-model-small-gu-0.42.zip");
        put("model-te", "https://alphacephei.com/vosk/models/vosk-model-small-te-0.42.zip");
        put("model-zh", "https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip");
        put("model-ja", "https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip");
        put("model-ko", "https://alphacephei.com/vosk/models/vosk-model-small-ko-0.22.zip");
        put("model-en", "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip");
    }};

    public ModelDownloadManager(Context context) {
        this.context = context;
        this.prefs = context.getSharedPreferences("ModelDownloads", Context.MODE_PRIVATE);
    }

    public void downloadModel(
        String modelName,
        ModelProgressCallback onProgress,
        ModelSuccessCallback onSuccess,
        ModelErrorCallback onError
    ) {
        // check internet connectivity first
        if (!isInternetAvailable()) {
            mainHandler.post(() -> onError.onError("No internet connection available. Please check your network and try again."));
            return;
        }

        downloadExecutor.execute(() -> {
            try {
                String modelUrl = modelUrls.get(modelName);
                if (modelUrl == null) {
                    throw new Exception("Model URL not found for " + modelName);
                }

                Log.d(TAG, "Starting download for " + modelName + " from " + modelUrl);

                // use cache directory instead of files directory
                File modelDir = new File(context.getCacheDir(), "model/" + modelName);
                cleanupModelDirectory(modelDir);
                modelDir.mkdirs();

                // mark as in-progress for this session and reset progress
                markInProgress(modelName, true);
                persistProgress(modelName, 0);

                // download and extract model
                downloadAndExtractModel(modelUrl, modelDir, onProgress);

                // verify model integrity
                if (verifyModel(modelDir)) {
                    Log.d(TAG, "Model " + modelName + " downloaded and verified successfully");
                    // ensure 100% persisted and clear in-progress for this session
                    persistProgress(modelName, 100);
                    markInProgress(modelName, false);
                    mainHandler.post(onSuccess::onSuccess);
                } else {
                    markInProgress(modelName, false);
                    mainHandler.post(() -> onError.onError("Model verification failed - required files missing"));
                }

            } catch (Exception e) {
                Log.e(TAG, "Download failed for " + modelName, e);
                String errorMessage = getErrorMessage(e);
                markInProgress(modelName, false);
                mainHandler.post(() -> onError.onError(errorMessage));
            }
        });
    }

    private String getErrorMessage(Exception e) {
        String message = e.getMessage();

        if (message != null) {
            if (message.contains("timeout")) {
                return "Download timeout. Please check your internet connection and try again.";
            } else if (message.contains("connection")) {
                return "Connection failed. Please check your internet connection and try again.";
            } else if (message.contains("network")) {
                return "Network error. Please check your internet connection and try again.";
            }
        }

        return "Download failed: " + (message != null ? message : "Unknown error");
    }

    private void downloadAndExtractModel(
        String url,
        File targetDir,
        ModelProgressCallback onProgress
    ) throws Exception {

        HttpURLConnection connection = (HttpURLConnection) new URI(url).toURL().openConnection();
        connection.setConnectTimeout(30000);
        connection.setReadTimeout(60000);

        // prefer long content length to avoid 32-bit overflow on large files
        long totalSize;
        try {
            totalSize = connection.getContentLengthLong();
        } catch (Exception ignored) {
            totalSize = connection.getContentLength();
        }

        InputStream inputStream = connection.getInputStream();

        File tempFile = new File(context.getCacheDir(), "temp_model_" + System.currentTimeMillis() + ".zip");
        FileOutputStream outputStream = new FileOutputStream(tempFile);

        int bytesRead;
        long downloaded = 0L;
        byte[] buffer = new byte[8192];

        Log.d(TAG, "Downloading model file (total " + formatBytes(totalSize) + ")");

        while ((bytesRead = inputStream.read(buffer)) != -1) {
            outputStream.write(buffer, 0, bytesRead);
            downloaded += bytesRead;

            if (totalSize > 0L) {
                int progress = (int) Math.min(Math.max((downloaded * 100L) / totalSize, 0), 95);
                mainHandler.post(() -> onProgress.onProgress(progress));
            }
        }

        inputStream.close();
        outputStream.close();

        Log.d(TAG, "Download completed, extracting to " + targetDir.getAbsolutePath());

        // update progress to 95% (download complete)
        mainHandler.post(() -> onProgress.onProgress(95));

        // extract ZIP file
        try {
            extractZipFile(tempFile, targetDir);
            Log.d(TAG, "ZIP extraction completed successfully");
        } catch (Exception e) {
            Log.e(TAG, "ZIP extraction failed", e);
            throw new Exception("Failed to extract model files: " + e.getMessage());
        } finally {
            // clean up temp file
            if (tempFile.exists()) {
                tempFile.delete();
                Log.d(TAG, "Temporary ZIP file deleted");
            }
        }

        // update progress to 100% (extraction complete)
        mainHandler.post(() -> onProgress.onProgress(100));

        Log.d(TAG, "Model extraction completed");
    }

    private String formatBytes(long bytes) {
        if (bytes >= 1_000_000_000L) {
            return String.format("%.1f GB", bytes / 1_000_000_000.0);
        } else if (bytes >= 1_000_000L) {
            return String.format("%.1f MB", bytes / 1_000_000.0);
        } else if (bytes >= 1_000L) {
            return String.format("%.1f KB", bytes / 1_000.0);
        } else {
            return bytes + " B";
        }
    }

    private void extractZipFile(File zipFile, File targetDir) throws Exception {
        Log.d(TAG, "Starting ZIP extraction to " + targetDir.getAbsolutePath());

        if (targetDir.exists()) {
            deleteRecursively(targetDir);
        }
        targetDir.mkdirs();

        String topLevelPrefix = findCommonTopLevelDir(zipFile);
        ZipInputStream zipInputStream = new ZipInputStream(new FileInputStream(zipFile));
        ZipEntry entry = zipInputStream.getNextEntry();

        try {
            while (entry != null) {
                String entryName = entry.getName();

                if (topLevelPrefix != null && !topLevelPrefix.isEmpty() && entryName.startsWith(topLevelPrefix + "/")) {
                    entryName = entryName.substring((topLevelPrefix + "/").length());
                    if (entryName.isEmpty()) {
                        entry = zipInputStream.getNextEntry();
                        continue;
                    }
                }

                File file = new File(targetDir, entryName);
                if (!file.getCanonicalPath().startsWith(targetDir.getCanonicalPath())) {
                    entry = zipInputStream.getNextEntry();
                    continue;
                }

                if (entry.isDirectory()) {
                    file.mkdirs();
                } else {
                    if (file.getParentFile() != null) {
                        file.getParentFile().mkdirs();
                    }

                    FileOutputStream outputStream = new FileOutputStream(file);
                    byte[] buffer = new byte[8192];
                    int bytesRead;

                    try {
                        while ((bytesRead = zipInputStream.read(buffer)) != -1) {
                            outputStream.write(buffer, 0, bytesRead);
                        }
                        outputStream.flush();
                    } finally {
                        outputStream.close();
                    }
                }

                entry = zipInputStream.getNextEntry();
            }

            Log.d(TAG, "ZIP extraction completed successfully");

        } catch (Exception e) {
            Log.e(TAG, "Error during ZIP extraction", e);
            throw e;
        } finally {
            zipInputStream.close();
        }
    }

    private void listFilesRecursively(File dir, List<File> files) {
        if (dir.isDirectory()) {
            File[] children = dir.listFiles();
            if (children != null) {
                for (File child : children) {
                    files.add(child);
                    if (child.isDirectory()) {
                        listFilesRecursively(child, files);
                    }
                }
            }
        }
    }

    private void deleteRecursively(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursively(child);
                }
            }
        }
        file.delete();
    }

    private String findCommonTopLevelDir(File zipFile) {
        Set<String> seen = new HashSet<>();
        try (ZipInputStream zis = new ZipInputStream(new FileInputStream(zipFile))) {
            ZipEntry e = zis.getNextEntry();
            while (e != null) {
                String name = e.getName();
                int idx = name.indexOf('/');
                if (idx > 0) {
                    seen.add(name.substring(0, idx));
                } else if (!e.isDirectory()) {
                    // there is a file at root; no common top-level dir
                    return null;
                }
                e = zis.getNextEntry();
            }
        } catch (Exception ignored) {
            return null;
        }
        return seen.size() == 1 ? seen.iterator().next() : null;
    }

    public boolean verifyModel(File modelDir) {
        Log.d(TAG, "Verifying model at: " + modelDir.getAbsolutePath());

        if (!modelDir.exists() || !modelDir.isDirectory()) {
            Log.d(TAG, "Model directory does not exist or is not a directory");
            return false;
        }

        List<File> allFiles = new ArrayList<>();
        listFilesRecursively(modelDir, allFiles);
        Set<String> signatures = collectModelFileSignatures(modelDir, allFiles);
        if (signatures.isEmpty()) {
            Log.d(TAG, "Model directory has no files");
            return false;
        }

        Set<String> matchedFiles = new HashSet<>();

        boolean hasAcoustic = matches(signatures, matchedFiles, "am/final.mdl", "final.mdl");
        boolean hasGraph = matches(signatures, matchedFiles, "graph/hclg.fst", "hclg.fst", "gr.fst");
        boolean hasConfig = matches(signatures, matchedFiles, "conf/model.conf", "conf/mfcc.conf", "mfcc.conf");
        boolean hasIvector = matches(signatures, matchedFiles, "ivector/final.ie", "ivector/final.dubm", "ivector/final.mat");
        boolean hasPhones = matches(signatures, matchedFiles, "graph/phones/word_boundary.int", "word_boundary.int", "phones.txt");
        boolean hasDisambig = matches(signatures, matchedFiles, "disambig_tid.int");

        int supportingCount = 0;
        if (hasGraph) supportingCount++;
        if (hasConfig) supportingCount++;
        if (hasIvector) supportingCount++;
        if (hasPhones) supportingCount++;
        if (hasDisambig) supportingCount++;

        boolean isValid = hasAcoustic && supportingCount >= 2;
        Log.d(TAG, "Model verification result: " + isValid + " (found " + matchedFiles.size() + " key files)");
        if (!matchedFiles.isEmpty()) {
            Log.d(TAG, "Matched key files: " + matchedFiles);
        }
        if (!isValid) {
            List<String> sample = new ArrayList<>();
            for (String signature : signatures) {
                sample.add(signature);
                if (sample.size() >= 10) {
                    break;
                }
            }
            Log.d(TAG, "Sample files for troubleshooting: " + sample);
        }

        return isValid;
    }

    private Set<String> collectModelFileSignatures(File rootDir, List<File> allFiles) {
        Set<String> signatures = new HashSet<>();
        String basePath = rootDir.getAbsolutePath();
        if (!basePath.endsWith(File.separator)) {
            basePath = basePath + File.separator;
        }
        for (File file : allFiles) {
            if (file == null || !file.isFile()) {
                continue;
            }
            String absolute = file.getAbsolutePath();
            if (!absolute.startsWith(basePath)) {
                continue;
            }
            String relative = absolute.substring(basePath.length());
            if (!relative.isEmpty()) {
                signatures.add(relative.replace('\\', '/').toLowerCase(Locale.ROOT));
            }
        }
        return signatures;
    }

    private boolean matches(Set<String> signatures, Set<String> matchedFiles, String... suffixes) {
        for (String suffix : suffixes) {
            for (String signature : signatures) {
                if (signature.endsWith(suffix)) {
                    matchedFiles.add(signature);
                    return true;
                }
            }
        }
        return false;
    }

    public boolean isModelDownloaded(String modelName) {
        File modelDir = new File(context.getCacheDir(), "model/" + modelName);
        Log.d(TAG, "Checking if model " + modelName + " is downloaded");

        if (!modelDir.exists()) {
            return false;
        }

        return verifyModel(modelDir);
    }

    public File getModelDirectory(String modelName) {
        return new File(context.getCacheDir(), "model/" + modelName);
    }

    private void markInProgress(String modelName, boolean inProgress) {
        SharedPreferences.Editor editor = prefs.edit();
        String inProgressKey = getInProgressKey(modelName);
        String sessionKey = getSessionKey(modelName);
        String progressKey = getProgressKey(modelName);
        if (inProgress) {
            editor.putBoolean(inProgressKey, true);
            editor.putString(sessionKey, sessionId);
        } else {
            editor.remove(inProgressKey);
            editor.remove(sessionKey);
            editor.remove(progressKey);
        }
        editor.apply();
    }

    private void persistProgress(String modelName, int progress) {
        prefs.edit().putInt(getProgressKey(modelName), Math.max(0, Math.min(100, progress))).apply();
    }

    public boolean isDownloadInProgress(String modelName) {
        String inProgressKey = getInProgressKey(modelName);
        if (!prefs.getBoolean(inProgressKey, false)) {
            return false;
        }

        String sessionKey = getSessionKey(modelName);
        String storedSession = prefs.getString(sessionKey, null);
        if (!sessionId.equals(storedSession)) {
            Log.d(TAG, "Detected stale download session for " + modelName + ". Cleaning up cached data.");
            cleanupModelDirectory(new File(context.getCacheDir(), "model/" + modelName));
            markInProgress(modelName, false);
            return false;
        }

        return true;
    }

    public long getModelSize(String modelName) {
        File modelDir = new File(context.getCacheDir(), "model/" + modelName);
        if (!modelDir.exists()) return 0;

        List<File> files = new ArrayList<>();
        listFilesRecursively(modelDir, files);
        return files.stream().filter(File::isFile).mapToLong(File::length).sum();
    }

    private String getInProgressKey(String modelName) {
        return "download_in_progress_" + modelName;
    }

    private String getSessionKey(String modelName) {
        return "download_session_" + modelName;
    }

    private String getProgressKey(String modelName) {
        return "download_progress_" + modelName;
    }

    private void cleanupModelDirectory(File modelDir) {
        if (modelDir.exists()) {
            deleteRecursively(modelDir);
        }
    }

    private boolean isInternetAvailable() {
        try {
            ConnectivityManager connectivityManager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (connectivityManager == null) return false;

            android.net.Network network = connectivityManager.getActiveNetwork();
            if (network == null) return false;

            NetworkCapabilities networkCapabilities = connectivityManager.getNetworkCapabilities(network);
            if (networkCapabilities == null) return false;

            return networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET);
        } catch (Exception e) {
            Log.e(TAG, "Error checking internet connectivity", e);
            return false;
        }
    }

    // callback interfaces
    public interface ModelProgressCallback {
        void onProgress(int progress);
    }

    public interface ModelSuccessCallback {
        void onSuccess();
    }

    public interface ModelErrorCallback {
        void onError(String error);
    }
}
