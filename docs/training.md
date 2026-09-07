# Training Guide

## Prerequisites

- Docker + NVIDIA Container Toolkit (for GPU)
- NVIDIA GPU with CUDA 12.4 support
- ~20 GB free disk space (HuggingFace model cache + dataset)

---

## 1. Environment Setup

### Docker (Recommended)

```bash
# Build the training container
docker compose build

# Start in interactive mode
docker compose up -d
docker compose exec cdac bash
```

The container is based on `pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime` and mounts the project directory at `/workspace`.

All caches (HuggingFace, Torch, pip) persist in `./cache/` on the host.

### Local (without Docker)

```bash
pip install -r requirements.txt
```

Requires Python ≥ 3.10 and PyTorch ≥ 2.6 with CUDA support.

---

## 2. Prepare Dataset

The model is trained on the **SNIPS NLU Benchmark** dataset (7 intents, ~13k training examples).

```bash
# Inside the container
python ml/src/prepare_data.py \
    --raw_dir ml/data/raw \
    --output_dir ml/data/processed
```

For the augmented V4 split:

```bash
python ml/src/augment_v4.py \
    --input_dir ml/data/processed \
    --output_dir ml/data/processed_v4
```

---

## 3. Training

### V3 Architecture (Recommended)

```bash
python ml/src/train_v3.py \
    --data_dir ml/data/processed_v4 \
    --output_dir ml/checkpoints/my_run \
    --backbone microsoft/MiniLM-L12-H384-uncased \
    --epochs 4 \
    --batch_size 32 \
    --lr 3e-5 \
    --slot_loss_weight 1.5 \
    --seed 42
```

**Key arguments:**

| Argument | Default | Description |
|---|---|---|
| `--backbone` | `microsoft/MiniLM-L12-H384-uncased` | HuggingFace encoder |
| `--epochs` | 4 | Training epochs |
| `--batch_size` | 32 | Per-device batch size |
| `--lr` | 3e-5 | Peak learning rate |
| `--slot_loss_weight` | 1.5 | Weight for slot loss vs intent loss |
| `--warmup_ratio` | 0.1 | Linear warmup fraction |
| `--max_length` | 48 | Max tokenized sequence length |
| `--seed` | 42 | Random seed |

### Warm-start from V2 baseline

```bash
python ml/src/train_v3.py \
    --data_dir ml/data/processed_v4 \
    --output_dir ml/checkpoints/v3_warmstart \
    --baseline_checkpoint ml/checkpoints/v2_best \
    --epochs 4
```

V3's new context layers (intent embedding, global context projection) are zero-initialized, so warm-start is safe — the model initially behaves like V2 and gradually learns to use the context signals.

---

## 4. Monitoring Training

TensorBoard logs are written to `--output_dir/tb_logs/`:

```bash
tensorboard --logdir ml/checkpoints/my_run/tb_logs
```

Training also prints epoch-level summaries:

```
Epoch 1/4
  loss        : 0.1453
  intent acc  : 0.9871
  slot F1     : 0.9540
  exact frame : 0.8957
  >>> NEW BEST MODEL
```

---

## 5. Evaluation

```bash
# Evaluate with all decoding strategies
python ml/src/evaluate_final.py \
    --checkpoint ml/checkpoints/my_run \
    --data_dir ml/data/processed_v4 \
    --split test
```

Output JSON with 4 decoding strategies:
- `raw` — argmax, no constraints
- `intent_mask` — mask slots invalid for predicted intent
- `intent_mask_bio` — mask + BIO-constrained Viterbi (recommended)
- `oracle_intent_bio` — upper bound using gold intent

---

## 6. Export to ONNX

```bash
python ml/src/export_onnx.py \
    --checkpoint ml/checkpoints/my_run \
    --output ml/exported/command_slm_fp32.onnx
```

Verify parity between PyTorch and ONNX outputs:

```bash
python ml/src/check_onnx_parity.py \
    --checkpoint ml/checkpoints/my_run \
    --onnx ml/exported/command_slm_fp32.onnx
```

---

## 7. INT8 Quantization

```bash
# Dynamic INT8 quantization
python ml/src/quantize_onnx.py \
    --input ml/exported/command_slm_fp32.onnx \
    --output ml/exported/command_slm_int8.onnx

# Evaluate the quantized model
python ml/src/evaluate_onnx.py \
    --onnx ml/exported/command_slm_int8.onnx \
    --checkpoint ml/checkpoints/my_run \
    --data_dir ml/data/processed_v4 \
    --split validation
```

Quantization sweep across strategies:

```bash
python ml/src/quantize_sweep.py \
    --checkpoint ml/checkpoints/my_run \
    --input ml/exported/command_slm_fp32.onnx \
    --output_dir ml/results/quant_sweep
```

---

## 8. Prepare Mobile Bundle

Copy artifacts to the mobile bundle directory:

```bash
mkdir -p ml/final/mobile_bundle/tokenizer

cp ml/exported/command_slm_int8.onnx ml/final/mobile_bundle/
cp ml/checkpoints/my_run/id2intent.json ml/final/mobile_bundle/
cp ml/checkpoints/my_run/id2slot.json ml/final/mobile_bundle/
cp ml/checkpoints/my_run/intent_slot_compat.json ml/final/mobile_bundle/
cp ml/checkpoints/my_run/model_config.json ml/final/mobile_bundle/
cp -r ml/checkpoints/my_run/tokenizer/ ml/final/mobile_bundle/tokenizer/
```

Then copy into the Flutter assets:

```bash
cp -r ml/final/mobile_bundle/ mobile/cdac_assistant/assets/
```

---

## Training Results (Champion V4)

| Epoch | Train Loss | Intent Acc | Slot F1 | Exact Frame |
|---|---|---|---|---|
| 1 | 0.1453 | 98.71% | 95.40% | 89.57% |
| **2** | **0.1275** | **98.71%** | **95.53%** | **89.71%** ✓ best |
| 3 | 0.1138 | 98.71% | 95.53% | 89.57% |
| 4 | 0.1111 | 98.71% | 95.48% | 89.71% |

Best checkpoint saved at epoch 2. Overfitting observed after epoch 2 (loss continues to drop, metrics plateau).
