# Evaluation Methodology & Results

## Dataset: SNIPS NLU Benchmark

The model is evaluated on the **SNIPS Natural Language Understanding benchmark**:

- **7 intents:** AddToPlaylist, BookRestaurant, GetWeather, PlayMusic, RateBook, SearchCreativeWork, SearchScreeningEvent
- **39 slot types** (72 BIO labels including B- and I- prefixes + O)
- **Train:** ~13,084 examples | **Validation:** ~700 examples | **Test:** ~700 examples

---

## Metrics

### Intent Accuracy
Percentage of utterances where the predicted intent matches the gold intent.

```
intent_accuracy = correct_intents / total_utterances
```

### Slot F1
Token-level F1 score over all slot entities, computed with the `seqeval` library:

```python
from seqeval.metrics import f1_score
slot_f1 = f1_score(gold_sequences, pred_sequences)
```

This is a **span-level** metric — a slot entity is counted as correct only if both the boundary and the type are exactly correct.

### Slot Sentence Accuracy
Percentage of utterances where **all** slot labels are predicted correctly.

### Exact Frame Accuracy
Percentage of utterances where **both** the intent and **all** slot labels are correct. This is the strictest and most informative metric.

```
exact_frame_accuracy = utterances_with_correct_intent_AND_all_slots / total
```

---

## Decoding Strategies

The evaluation script tests four decoding strategies to isolate different sources of error:

### 1. `raw`
Simple argmax decoding — no constraints applied.

### 2. `intent_mask`
After predicting the intent, zero out logits for slots that are incompatible with that intent (using `intent_slot_compat.json`). Then argmax.

### 3. `intent_mask_bio` ⭐ (Deployed)
1. Mask incompatible slots (as above)
2. Apply **BIO-constrained Viterbi decoding**:
   - Legal start states: `O`, `B-*`
   - Legal transitions: `I-X` can only follow `B-X` or `I-X`
   - Illegal transitions score: `−∞`

This prevents structurally invalid BIO sequences (e.g., `I-artist` after `O`).

### 4. `oracle_intent_bio`
Use the **gold intent** (instead of predicted) for slot masking + Viterbi. This gives the theoretical upper bound achievable with perfect intent prediction.

---

## Results: Champion V4 Model

### Validation Set

| Epoch | Intent Acc | Slot F1 | Exact Frame | Notes |
|---|---|---|---|---|
| 1 | 98.71% | 95.40% | 89.57% | |
| **2** | **98.71%** | **95.53%** | **89.71%** | ✅ Best checkpoint |
| 3 | 98.71% | 95.53% | 89.57% | |
| 4 | 98.71% | 95.48% | 89.71% | |

### Test Set (Champion V4, all decoding strategies)

| Strategy | Intent Acc | Slot F1 | Slot Sent Acc | Exact Frame |
|---|---|---|---|---|
| `raw` | 98.43% | 95.27% | 89.14% | 89.00% |
| `intent_mask` | 98.43% | 95.19% | 89.00% | 89.00% |
| **`intent_mask_bio`** | **98.43%** | **95.62%** | **89.86%** | **89.86%** |
| `oracle_intent_bio` | 100.00% | 96.18% | 91.14% | 91.14% |

### Analysis

- **Intent accuracy** is stable across strategies (98.43%) — intent prediction is essentially saturated.
- **BIO Viterbi** adds +0.43% Slot F1 and +0.86% Exact Frame Accuracy over raw argmax.
- The **oracle intent** upper bound reveals ~1.28% Exact Frame Accuracy is lost due to intent misclassifications.
- Intent errors contribute more to frame errors than slot errors do.

---

## ONNX Quantization Impact

Evaluating on the validation set:

| Model | Slot F1 | Exact Frame | Size |
|---|---|---|---|
| FP32 ONNX | 95.53% | 89.71% | ~134 MB |
| **INT8 ONNX** | **95.50%** | **89.57%** | **~34 MB** |

INT8 quantization causes a negligible drop (< 0.2%) while reducing model size by **4×**.

---

## Error Analysis

See `ml/results/v3_decoder_error_analysis.log` for per-utterance error breakdowns.

Common failure patterns:
1. **Multi-word slot boundary errors** — last word of a slot missed (I→O transition too early)
2. **Ambiguous artist vs. entity name** — e.g., "Beethoven" tagged as `entity_name` instead of `artist`
3. **Rare slot types** — slots with few training examples (e.g., `geographic_poi`) have lower recall
4. **Intent confusion** — `SearchCreativeWork` vs. `RateBook` for rating-related queries
