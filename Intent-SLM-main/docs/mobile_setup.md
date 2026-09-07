# Mobile App Setup Guide

The mobile app is a Flutter Android application that runs the Intent SLM entirely on-device.

---

## Prerequisites

- Flutter SDK ≥ 3.12.2 ([install](https://flutter.dev/docs/get-started/install))
- Android Studio or VS Code with Flutter plugin
- Android device or emulator (API 26+, ARM64 recommended)
- NDK installed (for native ONNX Runtime and Whisper bindings)

---

## 1. Clone and Navigate

```bash
cd mobile/cdac_assistant
```

---

## 2. Place Model Assets

The following files must be in `assets/` before building:

```
assets/
├── models/
│   └── command_slm_int8.onnx       # 34 MB INT8 ONNX model
├── tokenizer/
│   └── vocab.txt                   # BERT WordPiece vocabulary
├── config/
│   ├── model_config.json
│   ├── id2intent.json
│   ├── id2slot.json
│   └── intent_slot_compat.json
└── asr/
    └── whisper/
        └── ggml-base.en.bin        # Whisper base English model (~148 MB)
```

Copy from the ML pipeline output:
```bash
cp ../../ml/final/mobile_bundle/command_slm_int8.onnx assets/models/
cp -r ../../ml/final/mobile_bundle/tokenizer/ assets/tokenizer/
cp ../../ml/final/mobile_bundle/{model_config,id2intent,id2slot,intent_slot_compat}.json assets/config/
```

Download the Whisper model:
```bash
# From HuggingFace or ggerganov/whisper.cpp releases
wget -O assets/asr/whisper/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

---

## 3. Install Dependencies

```bash
flutter pub get
```

---

## 4. Android Permissions

The following permissions are declared in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

- `RECORD_AUDIO` — required for microphone capture
- `SYSTEM_ALERT_WINDOW` — required for the floating Edge Agent overlay
- `FOREGROUND_SERVICE` — required for background overlay service

---

## 5. Build and Run

### Debug

```bash
flutter run
```

### Release APK

```bash
flutter build apk --release
```

APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Install on Device

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## 6. App Structure

The app has four tabs:

### 🧠 Assistant Tab
- Push-to-talk voice interface
- Displays transcription, intent, confidence, and extracted slots
- Shows NLU inference latency

### 📱 Device Hub Tab
- Lists available device action categories
- Shows action history

### ✨ Edge Agent Tab
- Enable/disable the floating overlay bubble
- The overlay lets you issue voice commands from any app

### 🔬 Project Tab
- Internal research dashboard
- Shows model info, run benchmarks, inspect raw model outputs

---

## 7. Third-Party Dependencies

### `flutter_screen_overlay` (local)

Located at `third_party/flutter_screen_overlay`. This custom plugin implements:
- Android `SYSTEM_ALERT_WINDOW` overlay service
- Separate Flutter engine for the overlay process
- Bidirectional communication via method channels

### `whisper_ggml`

Wraps the [whisper.cpp](https://github.com/ggerganov/whisper.cpp) library for on-device ASR.
The `ggml-base.en.bin` model is bundled as a Flutter asset and copied to the app's data directory on first launch.

### `flutter_onnxruntime`

Wraps [ONNX Runtime](https://onnxruntime.ai/) for on-device neural network inference.
Supports INT8 quantized models on ARM64 Android devices.

---

## 8. Performance Notes

| Component | Typical Latency (mid-range phone) |
|---|---|
| Voice capture (2s command) | ~2000 ms (real-time) |
| Whisper transcription | 800–1500 ms |
| NLU tokenization | < 5 ms |
| ONNX INT8 inference | 30–80 ms |
| Viterbi decoding | < 2 ms |
| **Total end-to-end** | **~1–2.5 s** |

For best performance, use a device with an ARM64 processor and at least 4 GB RAM.

---

## 9. Troubleshooting

**Model not loading:** Ensure all asset files are in the correct paths and listed in `pubspec.yaml` under the `assets:` section.

**Microphone permission denied:** The app requests mic permission on first use. Grant it in Android Settings > Apps > CDAC Assistant > Permissions.

**Overlay not appearing:** Grant "Display over other apps" permission in Android Settings > Apps > Special App Access > Display over other apps.

**Whisper hallucinating:** This can happen with very short recordings or very noisy environments. The voice engine enforces minimum duration (700ms) and level (−55 dBFS) guards.
