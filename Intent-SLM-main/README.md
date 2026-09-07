# Intent SLM — On-Device Natural Language Understanding

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.6-red)](https://pytorch.org)
[![ONNX](https://img.shields.io/badge/ONNX-1.16%2B-green)](https://onnx.ai)

> **C-DAC Track B Submission** — A fully offline, on-device voice assistant powered by a custom-trained Small Language Model (SLM) for joint intent detection and slot filling, deployed as an Android app via Flutter and ONNX Runtime.

---

## 🎯 What This Project Does

Intent SLM listens to spoken voice commands, understands what the user wants (intent), and extracts key information (slots) — all **100% on-device** with no internet connection required.

**Example:**

| Voice Command | Intent | Slots |
|---|---|---|
| *"Play jazz by Miles Davis"* | `PlayMusic` | `genre=jazz`, `artist=Miles Davis` |
| *"What's the weather in Mumbai tomorrow?"* | `GetWeather` | `city=Mumbai`, `timeRange=tomorrow` |
| *"Book a table for 4 at an Italian restaurant"* | `BookRestaurant` | `party_size_number=4`, `cuisine=Italian` |

---

## 📐 Architecture

```
🎤 Microphone
     │
     ▼
┌─────────────────────┐
│    Voice Engine     │  Whisper ggml-base.en (offline ASR)
│    (Whisper)        │  WAV 16 kHz mono → clean transcript
└──────────┬──────────┘
           │ text
           ▼
┌─────────────────────┐
│     NLU Engine      │  BERT WordPiece tokenizer (Dart)
│     (SLM ONNX)      │  INT8 ONNX Model (34 MB)
│                     │  IntentConditionedSLM
│                     │   MiniLM-L12 encoder
│                     │   ├─ intent head (CLS → 7 classes)
│                     │   └─ conditioned slot head (72 BIO labels)
│                     │  BIO-constrained Viterbi decode
└──────────┬──────────┘
           │ intent + slots
           ▼
┌─────────────────────┐
│    Action Router    │  Maps NLU output → Android actions
└─────────────────────┘
```

### Model: `IntentConditionedCommandSLM`

A custom joint NLU model that uses the **predicted intent as conditioning signal for slot tagging**:

```
MiniLM-L12 encoder
    │
    ├──► Intent Classifier  → 7 intents  (CLS token)
    │
    └──► Slot Classifier   → 72 BIO labels (all tokens)
               ↑
         Conditioned by:
           • Global CLS context projection
           • Soft intent embedding (differentiable — no teacher forcing)
```

This design ensures **train and inference use identical computation** — no gold labels are injected during training.

---

## 🏆 Model Performance

Evaluated on the **SNIPS NLU** benchmark test set:

| Decoding Strategy | Intent Acc | Slot F1 | Exact Frame Acc |
|---|---|---|---|
| Raw argmax | 98.43% | 95.27% | 89.00% |
| Intent-masked | 98.43% | 95.19% | 89.00% |
| **Intent-masked + BIO Viterbi** | **98.43%** | **95.62%** | **89.86%** |
| Oracle intent + BIO Viterbi | 100.00% | 96.18% | 91.14% |

**Validation best (epoch 2):** Intent 98.71% · Slot F1 95.53% · Frame 89.71%

Model backbone: `microsoft/MiniLM-L12-H384-uncased` (33.5 M params) · INT8-quantized to **34 MB**

---

## 📁 Repository Structure

```
intent-slm/
├── ml/                          # ML training pipeline
│   ├── src/                     # Source code
│   │   ├── model_v3.py          # IntentConditionedCommandSLM architecture
│   │   ├── train_v3.py          # Training loop (V3/V4)
│   │   ├── dataset.py           # SNIPS dataset loader
│   │   ├── augment_v4.py        # Data augmentation
│   │   ├── evaluate_final.py    # Multi-strategy evaluation
│   │   ├── export_onnx.py       # PyTorch → ONNX export
│   │   ├── quantize_onnx.py     # INT8 dynamic quantization
│   │   ├── constrained_decoder.py  # BIO Viterbi decoder (Python)
│   │   └── infer.py             # Single-sample inference CLI
│   ├── final/                   # Final model artifacts
│   │   ├── champion_v4/         # Full-precision checkpoint (safetensors)
│   │   └── mobile_bundle/       # INT8 ONNX + config for mobile
│   └── results/                 # Training logs and evaluation JSONs
│
├── mobile/                      # Flutter Android app
│   └── cdac_assistant/
│       └── lib/
│           ├── main.dart                   # App entry point (4-tab shell)
│           ├── nlu_engine.dart             # ONNX inference + Viterbi decoder
│           ├── voice_engine.dart           # Whisper ASR integration
│           ├── action_router.dart          # NLU → Android action mapping
│           ├── action_dispatcher.dart      # Execute Android actions
│           ├── edge_agent_bridge.dart      # Overlay ↔ main app IPC
│           ├── edge_agent_overlay.dart     # Floating bubble UI
│           ├── intent_acceptance_gate.dart # Confidence-based guardrail
│           └── calculator_skill.dart       # Calculator agent skill
│
├── docs/                        # Documentation
│   ├── architecture.md          # Detailed architecture guide
│   ├── training.md              # How to train the model
│   ├── mobile_setup.md          # Flutter app setup guide
│   └── evaluation.md            # Evaluation methodology & results
│
├── Dockerfile                   # GPU training container
├── compose.yaml                 # Docker Compose for training
├── requirements.txt             # Python dependencies
└── README.md
```

---

## 🚀 Quick Start

### 1. Training (GPU Required)

```bash
# Start the GPU training container
docker compose up -d

# Prepare the SNIPS dataset
docker compose exec cdac python ml/src/prepare_data.py

# Train the model
docker compose exec cdac python ml/src/train_v3.py \
    --data_dir ml/data/processed_v4 \
    --output_dir ml/checkpoints/my_run \
    --epochs 4

# Export to ONNX + INT8 quantize
docker compose exec cdac python ml/src/export_onnx.py \
    --checkpoint ml/checkpoints/my_run \
    --output ml/exported/

docker compose exec cdac python ml/src/quantize_onnx.py \
    --input ml/exported/command_slm_fp32.onnx \
    --output ml/exported/command_slm_int8.onnx
```

### 2. Evaluate

```bash
docker compose exec cdac python ml/src/evaluate_final.py \
    --checkpoint ml/final/champion_v4 \
    --data_dir ml/data/processed_v4 \
    --split test
```

### 3. Inference (Python)

```bash
python ml/src/infer.py \
    --checkpoint ml/final/champion_v4 \
    --text "Play some jazz music by Miles Davis"
```

Output:
```json
{
  "intent": "PlayMusic",
  "confidence": 0.997,
  "slots": {
    "genre": "jazz",
    "artist": "Miles Davis"
  }
}
```

### 4. Mobile App

See [`docs/mobile_setup.md`](docs/mobile_setup.md) for full Flutter build instructions.

```bash
cd mobile/cdac_assistant
flutter pub get
flutter run --release
```

---

## 🔧 Python Requirements

```
Python >= 3.10
PyTorch >= 2.6  (CUDA 12.4 recommended for training)
transformers >= 4.44
datasets >= 2.20
onnxruntime >= 1.18
optimum >= 1.21
seqeval >= 1.2.2
```

Install: `pip install -r requirements.txt`

---

## 📱 Mobile Stack

| Component | Technology |
|---|---|
| Framework | Flutter 3.x (Dart) |
| ASR | Whisper ggml-base.en (`whisper_ggml`) |
| NLU inference | ONNX Runtime (`flutter_onnxruntime`) |
| Tokenizer | WordPiece BERT (`dart_bert_tokenizer`) |
| Android actions | `android_intent_plus` |
| Overlay UI | Custom `flutter_screen_overlay` |

---

## 🎤 Supported Intents

| Intent | Example Command |
|---|---|
| `PlayMusic` | *"Play some jazz by Coltrane"* |
| `GetWeather` | *"What's the weather in Delhi?"* |
| `BookRestaurant` | *"Book a Chinese restaurant for 2"* |
| `AddToPlaylist` | *"Add this song to my workout playlist"* |
| `RateBook` | *"Rate the Alchemist 5 stars"* |
| `SearchCreativeWork` | *"Find me a sci-fi novel"* |
| `SearchScreeningEvent` | *"Find movies showing tonight"* |

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgements

- [SNIPS NLU Dataset](https://github.com/snipsco/nlu-benchmark) — benchmark dataset
- [MiniLM](https://huggingface.co/microsoft/MiniLM-L12-H384-uncased) — backbone encoder by Microsoft
- [Whisper](https://github.com/openai/whisper) — ASR model by OpenAI
- [ONNX Runtime](https://onnxruntime.ai/) — cross-platform inference engine
- C-DAC for organizing the competition (Track B)
