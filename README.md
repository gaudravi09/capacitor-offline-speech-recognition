# Capacitor Offline Speech Recognition Plugin

A Capacitor plugin that provides offline speech-to-text functionality for Android and iOS platforms. The plugin uses the Vosk engine on both platforms for fully offline recognition with downloadable language models.

## Maintainers

| Maintainer | GitHub | Social |
| ---------- | ------ | ------ |
| Ravi Gaud  | [GaudRavi09](https://github.com/GaudRavi09) | - |

Maintenance Status: Actively Maintained

## Installation

To use npm

```bash
npm install capacitor-offline-speech-recognition
```

To use yarn

```bash
yarn add capacitor-offline-speech-recognition
```

Sync native files

```bash
npx cap sync
```

## Platform Support

- ✅ **Android** - Full offline support with Vosk models for 15+ languages
- ✅ **iOS** - Full offline support with Vosk models (uses Vosk instead of Apple's Speech framework)
- ❌ **Web** - Not supported (requires offline model files)

## System Requirements

### Android
- **Minimum SDK**: API level 24 (Android 7.0)
- **Target SDK**: API level 34 (Android 14)
- **Storage**: ~50MB per language model
- **RAM**: Minimum 2GB recommended for optimal performance

### iOS
- **Minimum iOS**: 14.0
- **Target iOS**: 17.0+
- **Storage**: ~50MB per language model
- **RAM**: Minimum 2GB recommended for optimal performance

### Dependencies
- **Capacitor**: ^5.0.0
- **Android**: Vosk Android SDK 0.3.70
- **iOS**: Vosk iOS static library (bundled xcframework), `Accelerate`, `AVFoundation`, `AudioToolbox`, and `SSZipArchive`

## iOS

### Minimum iOS Requirements

The plugin requires the following minimum iOS versions:

* **Minimum iOS**: 12.0
* **Target iOS**: 17.0
* **Deployment Target**: 12.0

### Permissions

Since iOS now uses Vosk (not Apple's Speech framework), only the microphone usage description is required in your app `Info.plist`:

* `NSMicrophoneUsageDescription` (`Privacy - Microphone Usage Description`)

### iOS Setup

1) Add the following permission to your iOS app's `Info.plist` file:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to microphone for speech recognition functionality.</string>
```

2) CocoaPods integration: after installing this plugin, run the following to integrate the bundled `libvosk.xcframework` and dependencies (`SSZipArchive`, `Accelerate`, `AVFoundation`, `AudioToolbox`):

```bash
cd ios/App
pod install
```

3) The plugin downloads and unzips Vosk language models on-demand into the app’s Documents directory.

## Android

### Minimum SDK Requirements

The plugin requires the following minimum SDK versions:

* **Minimum SDK**: API level 24 (Android 7.0)
* **Target SDK**: API level 34 (Android 14)
* **Compile SDK**: API level 34 (Android 14)

### Permissions

The plugin automatically includes the required permissions in its `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

**Permission Details:**
* `RECORD_AUDIO` - Required for speech recognition
* `INTERNET` - Required for model downloads from alphacephei.com
* `ACCESS_NETWORK_STATE` - Required for connectivity checks
* `READ_EXTERNAL_STORAGE` - Required for reading downloaded model files
* `WRITE_EXTERNAL_STORAGE` - Required for storing downloaded model files

### Android Setup

No additional configuration required. The plugin handles all permissions automatically through Capacitor's permission system.

**Note**: For Android 13+ (API level 33+), the `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` permissions are automatically managed by the system for app-specific storage.

## Example

```typescript
import { OfflineSpeechRecognition } from 'capacitor-offline-speech-recognition';

// Get supported languages
const languages = await OfflineSpeechRecognition.getSupportedLanguages();
console.log('Supported languages:', languages.languages);

// Download a language model
const downloadListener = await OfflineSpeechRecognition.addListener('downloadProgress', (progress) => {
  console.log(`Download progress: ${progress.progress}% - ${progress.message}`);
});

const downloadResult = await OfflineSpeechRecognition.downloadLanguageModel({ 
  language: 'en-us' 
});
console.log('Download result:', downloadResult);

// Remove download listener
await downloadListener.remove();

// Start speech recognition
const recognitionListener = await OfflineSpeechRecognition.addListener('recognitionResult', (result) => {
  console.log(`Recognized: ${result.text} (Final: ${result.isFinal})`);
});

await OfflineSpeechRecognition.startRecognition({ language: 'en-us' });

// Stop recognition
await OfflineSpeechRecognition.stopRecognition();

// Remove recognition listener
await recognitionListener.remove();
```

## API

<docgen-index>

* [`getSupportedLanguages()`](#getsupportedlanguages)
* [`getDownloadedLanguageModels()`](#getdownloadedlanguagemodels)
* [`downloadLanguageModel(...)`](#downloadlanguagemodel)
* [`startRecognition(...)`](#startrecognition)
* [`stopRecognition()`](#stoprecognition)
* [`addListener('downloadProgress', ...)`](#addlistenerdownloadprogress-)
* [`addListener('recognitionResult', ...)`](#addlistenerrecognitionresult-)
* [`removeAllListeners()`](#removealllisteners)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### getSupportedLanguages()

```typescript
getSupportedLanguages() => Promise<{ languages: Language[]; }>
```

Get all supported languages for speech recognition

**Returns:** <code>Promise&lt;{ languages: Language[]; }&gt;</code>

--------------------


### getDownloadedLanguageModels()

```typescript
getDownloadedLanguageModels() => Promise<{ models: DownloadedModel[]; }>
```

Get all downloaded language models on the device

**Returns:** <code>Promise&lt;{ models: DownloadedModel[]; }&gt;</code>

--------------------


### downloadLanguageModel(...)

```typescript
downloadLanguageModel(options: { language: string; }) => Promise<{ success: boolean; language: string; modelName?: string; message?: string; }>
```

Download a language model for offline use

| Param         | Type                               | Description                                         |
| ------------- | ---------------------------------- | --------------------------------------------------- |
| **`options`** | <code>{ language: string; }</code> | - <a href="#language">Language</a> code to download |

**Returns:** <code>Promise&lt;{ success: boolean; language: string; modelName?: string; message?: string; }&gt;</code>

--------------------


### startRecognition(...)

```typescript
startRecognition(options?: { language?: string | undefined; } | undefined) => Promise<void>
```

Start speech recognition

| Param         | Type                                | Description                                                                   |
| ------------- | ----------------------------------- | ----------------------------------------------------------------------------- |
| **`options`** | <code>{ language?: string; }</code> | - <a href="#language">Language</a> code for recognition (defaults to 'en-us') |

--------------------


### stopRecognition()

```typescript
stopRecognition() => Promise<void>
```

Stop speech recognition

--------------------


### addListener('downloadProgress', ...)

```typescript
addListener(eventName: 'downloadProgress', listenerFunc: (progress: DownloadProgress) => void) => Promise<{ remove: () => void; }>
```

Add listener for download progress updates

| Param              | Type                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------ |
| **`eventName`**    | <code>'downloadProgress'</code>                                                      |
| **`listenerFunc`** | <code>(progress: <a href="#downloadprogress">DownloadProgress</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;{ remove: () =&gt; void; }&gt;</code>

--------------------


### addListener('recognitionResult', ...)

```typescript
addListener(eventName: 'recognitionResult', listenerFunc: (result: RecognitionResult) => void) => Promise<{ remove: () => void; }>
```

Add listener for recognition results

| Param              | Type                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------ |
| **`eventName`**    | <code>'recognitionResult'</code>                                                     |
| **`listenerFunc`** | <code>(result: <a href="#recognitionresult">RecognitionResult</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;{ remove: () =&gt; void; }&gt;</code>

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Remove all listeners

--------------------


### Interfaces


#### Language

| Prop            | Type                |
| --------------- | ------------------- |
| **`code`**      | <code>string</code> |
| **`name`**      | <code>string</code> |
| **`modelFile`** | <code>string</code> |


#### DownloadedModel

| Prop           | Type                |
| -------------- | ------------------- |
| **`language`** | <code>string</code> |
| **`name`**     | <code>string</code> |
| **`path`**     | <code>string</code> |
| **`size`**     | <code>number</code> |


#### DownloadProgress

| Prop           | Type                |
| -------------- | ------------------- |
| **`progress`** | <code>number</code> |
| **`message`**  | <code>string</code> |


#### RecognitionResult

| Prop           | Type                 |
| -------------- | -------------------- |
| **`text`**     | <code>string</code>  |
| **`isFinal`**  | <code>boolean</code> |
| **`language`** | <code>string</code>  |

</docgen-api>

## Supported Languages

### Android (Vosk Models)
- English (US) - `en-us`
- German - `de`
- French - `fr`
- Spanish - `es`
- Portuguese - `pt`
- Chinese - `zh`
- Russian - `ru`
- Turkish - `tr`
- Vietnamese - `vi`
- Italian - `it`
- Hindi - `hi`
- Gujarati - `gu`
- Telugu - `te`
- Japanese - `ja`
- Korean - `ko`

### iOS (Vosk Models)
- English (US) - `en-us`
- German - `de`
- French - `fr`
- Spanish - `es`
- Portuguese - `pt`
- Chinese - `zh`
- Russian - `ru`
- Turkish - `tr`
- Vietnamese - `vi`
- Italian - `it`
- Hindi - `hi`
- Gujarati - `gu`
- Telugu - `te`
- Japanese - `ja`
- Korean - `ko`

## Platform Differences

| Feature | Android (Vosk) | iOS (Vosk) |
|---------|----------------|------------|
| **Models** | Downloaded Vosk models (50MB+ each) | Downloaded Vosk models (50MB+ each) |
| **Offline** | True offline (all languages) | True offline (all languages) |
| **Download** | Real model downloads from alphacephei.com | Real model downloads from alphacephei.com |
| **Languages** | 15+ Vosk models | 15+ Vosk models |
| **Storage** | App storage (cache/Documents) | App storage (Documents) |

## Permission Handling

### iOS
Only microphone permission is required. The plugin requests it when starting recognition.

### Android
The plugin uses Capacitor's permission system:
1. Automatically requests permissions when needed
2. Permissions requested before starting recognition or downloading models
3. Handles permission granted/denied scenarios

## Troubleshooting

### iOS Issues
- **Permission denied**: Check `NSMicrophoneUsageDescription` exists in Info.plist
- **No progress updates**: Ensure listener is registered before calling `downloadLanguageModel`
- **Linker errors**: Run `pod install` after plugin updates; ensure Pods include `Accelerate`, `AVFoundation`, `AudioToolbox`, `SSZipArchive`
- **Model verification failed**: Re-download the model; extraction may have failed or been interrupted

### Android Issues
- **Permission denied**: Check if user manually denied permissions
- **Model download fails**: Check internet permission and connectivity
- **Recognition fails**: Check microphone permission
- **Build errors**: Ensure minimum SDK 21 and target SDK 34
- **Vosk model loading fails**: Check if model files are corrupted or incomplete

### Common Issues
- **Models not downloading**: Check internet connection and storage permissions
- **Recognition not working**: Ensure microphone permission is granted
- **Language not supported**: Check if language is available on the device
- **App crashes on older devices**: Ensure device meets minimum requirements (Android 5.0+, iOS 12.0+)
- **Storage issues**: Ensure device has sufficient storage for model downloads (50MB+ per model)

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
