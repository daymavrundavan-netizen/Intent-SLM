# Architecture Guide

## Overview

Intent SLM is a joint NLU system consisting of:
1. **Voice Engine** — offline ASR using Whisper
2. **NLU Engine** — intent classification + slot filling via a custom SLM
3. **Action Router** — maps NLU output to Android device actions

---

## Model Architecture: `IntentConditionedCommandSLM`

### V3 Design Philosophy

Earlier NLU models treat intent and slot tagging as independent tasks (shared encoder, two heads). **Intent SLM V3** makes the slot head *conditioned* on the predicted intent, allowing the model to use high-level intent knowledge to refine slot boundaries.

```
Input Text
    │
    ▼
┌─────────────────────────────────────────────┐
│             MiniLM-L12 Encoder              │
│        (microsoft/MiniLM-L12-H384)          │
│  hidden_size = 384,  12 layers,  12 heads   │
└─────────┬────────────────────────┬──────────┘
          │ CLS token              │ all tokens
          ▼                        │
┌──────────────────┐               │
│ Intent Classifier│               │
│ Linear(384 → 7)  │               │
└────────┬─────────┘               │
         │ intent_logits           │
         │                         │
         ▼                         │
   softmax → intent_probs          │
         │                         │
         ▼                         │
   intent_probs @ intent_embedding │
   (7,) × (7, 384) = (384,)        │
         │                         │
         │ intent_context          │
         └──────────┐              │
                    ▼              ▼
           ┌────────────────────────────┐
           │  conditioned_output =      │
           │    sequence_output         │
           │    + global_context_proj   │
           │    + intent_context        │
           └──────────────┬────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   Slot Classifier     │
              │  Linear(384 → 72)     │
              └───────────────────────┘
                          │
                          ▼
               BIO-Constrained Viterbi
                          │
                          ▼
                    slot sequence
```

### Key Components

#### Backbone
- `microsoft/MiniLM-L12-H384-uncased`
- 12 layers, hidden_size=384, 12 attention heads
- ~33.5M parameters total (including classification heads)
- Uncased: all input lowercased + accent-stripped

#### Intent Head
- Single linear layer: `384 → num_intents (7)`
- Input: CLS token from the encoder output
- Output: raw logits → argmax for prediction, softmax for conditioning

#### Intent Embedding
- `nn.Embedding(7, 384)` — one learned vector per intent
- **Zero-initialized** at the start of V3 fine-tuning
- Allows smooth warm-start from V2 baseline checkpoint

#### Global Context Projection
- `nn.Linear(384, 384)` — sentence-level context from CLS
- **Zero-initialized** at the start of V3 fine-tuning
- Adds a global sentence representation to every token

#### Slot Head
- Single linear layer: `384 → num_slots (72)`
- Input: each token's conditioned representation
- Output: BIO tag logits per token

### Zero-Initialization Strategy

V3 context layers (`intent_embedding`, `global_context_proj`) start at zero:

```
conditioned_output = sequence_output
                   + 0 × global_context   (initially zero)
                   + 0 × intent_context   (initially zero)
                   ≈ sequence_output
```

This means **V3 starts behaving identically to V2** when warm-started from a V2 checkpoint, and gradually learns to use the context signals without catastrophic regression.

---

## Inference Pipeline (Mobile)

### Step 1: Voice Capture
- `record` package captures **WAV, 16kHz, mono** audio
- Auto-gain and noise suppression enabled
- Min duration: 700ms · Min level: −55 dBFS

### Step 2: Transcription (Whisper)
- `whisper_ggml` runs `ggml-base.en` entirely on-device
- Command vocabulary bias injected via `initialPrompt`
- Non-speech annotations `[music]`, `(noise)` are stripped

### Step 3: Tokenization (Dart)
- `dart_bert_tokenizer` implements WordPiece (BERT uncased)
- Adds `[CLS]` + `[SEP]` tokens
- Pads to `max_length=48`
- Tracks `firstPieceIndexes` (for slot aggregation) and `wordSpans` (for span extraction)

### Step 4: ONNX Inference
- `flutter_onnxruntime` runs the INT8 model
- Inputs: `input_ids`, `attention_mask`, `token_type_ids` — shape `[1, 48]`
- Outputs: `intent_logits` `[1, 7]`, `slot_logits` `[1, 48, 72]`

### Step 5: Decoding

**Intent:** `argmax(intent_logits)` → intent ID → intent name

**Slots (BIO Viterbi):**
1. Extract only first-WordPiece logit per original word
2. Apply `intent_slot_compat` mask — zero out slots illegal for the predicted intent
3. Run BIO-constrained Viterbi:
   - Legal start: only `O` or `B-*`
   - Legal transition: `I-X` may only follow `B-X` or `I-X`
4. Aggregate word spans → slot value strings

### Step 6: Confidence Gate
- `intent_acceptance_gate.dart` applies a confidence threshold
- Rejects predictions with softmax probability below the threshold
- User is prompted to repeat if rejected

### Step 7: Action Routing
- `action_router.dart` maps `(intent, slots)` → Android action
- `action_dispatcher.dart` executes via `android_intent_plus`

---

## Edge Agent (Floating Overlay)

The Edge Agent is a **system-level floating bubble** (implemented via Android's `SYSTEM_ALERT_WINDOW` permission) that:
- Lives above all other apps
- Runs a **separate Flutter entry point** (`overlayMain()`)
- Communicates with the main app process via `edge_agent_bridge.dart` (IPC)
- Allows push-to-talk from any screen

```
Main App Process          Overlay Process
─────────────────         ────────────────
EdgeAgentBridge  ◄──────► EdgeAgentOverlay
  (receives cmd)  (IPC)    (sends cmd + transcription)
       │
       ▼
  ActionDispatcher
```

---

## Deployment Artifacts

| File | Size | Description |
|---|---|---|
| `champion_v4/model.safetensors` | 134 MB | Full-precision PyTorch checkpoint |
| `mobile_bundle/command_slm_int8.onnx` | 34 MB | INT8 quantized ONNX (deployed in APK) |
| `mobile_bundle/tokenizer/vocab.txt` | ~230 KB | BERT WordPiece vocabulary |
| `mobile_bundle/id2intent.json` | < 1 KB | Intent ID → name mapping |
| `mobile_bundle/id2slot.json` | < 2 KB | Slot ID → BIO label mapping |
| `mobile_bundle/intent_slot_compat.json` | 5 KB | Per-intent allowed slot IDs |
| `mobile_bundle/model_config.json` | < 1 KB | Model hyperparameters |
