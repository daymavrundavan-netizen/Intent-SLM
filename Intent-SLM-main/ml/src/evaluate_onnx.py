import argparse
import json
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import torch
from seqeval.metrics import f1_score
from transformers import AutoTokenizer

from constrained_decoder import constrained_viterbi


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_jsonl(path):
    examples = []

    with open(path, encoding="utf-8") as f:
        for line in f:
            examples.append(json.loads(line))

    return examples


def percentile(values, q):
    return float(np.percentile(values, q))


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--model",
        required=True,
    )

    parser.add_argument(
        "--export-dir",
        required=True,
    )

    parser.add_argument(
        "--data-dir",
        default="/workspace/ml/data/processed",
    )

    parser.add_argument(
        "--split",
        choices=["train", "valid"],
        default="valid",
    )

    args = parser.parse_args()

    model_path = Path(args.model)
    export_dir = Path(args.export_dir)
    data_dir = Path(args.data_dir)

    config = load_json(
        export_dir / "model_config.json"
    )

    id2intent = load_json(
        export_dir / "id2intent.json"
    )

    id2slot = load_json(
        export_dir / "id2slot.json"
    )

    compatibility = load_json(
        export_dir / "intent_slot_compat.json"
    )

    tokenizer = AutoTokenizer.from_pretrained(
        export_dir / "tokenizer",
        use_fast=True,
    )

    session = ort.InferenceSession(
        str(model_path),
        providers=[
            "CPUExecutionProvider"
        ],
    )

    examples = load_jsonl(
        data_dir / f"{args.split}.jsonl"
    )

    total = 0
    intent_correct = 0
    slot_sentence_correct = 0
    frame_correct = 0

    gold_sequences = []
    pred_sequences = []

    inference_times_ms = []

    print("=" * 76)
    print("CDAC ONNX DEPLOYMENT EVALUATION")
    print("=" * 76)
    print("Model :", model_path)
    print("Split :", args.split)
    print("ORT   :", ort.__version__)
    print()

    for example_index, example in enumerate(examples):

        words = example["tokens"]
        gold_slots = example["slots"]
        gold_intent = example["intent"]

        encoding = tokenizer(
            words,
            is_split_into_words=True,
            truncation=True,
            padding="max_length",
            max_length=config["max_length"],
            return_tensors="np",
        )

        word_ids = encoding.word_ids(
            batch_index=0
        )

        input_ids = (
            encoding["input_ids"]
            .astype(np.int64)
        )

        attention_mask = (
            encoding["attention_mask"]
            .astype(np.int64)
        )

        if "token_type_ids" in encoding:
            token_type_ids = (
                encoding["token_type_ids"]
                .astype(np.int64)
            )
        else:
            token_type_ids = np.zeros_like(
                input_ids,
                dtype=np.int64,
            )

        ort_inputs = {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
            "token_type_ids": token_type_ids,
        }

        start = time.perf_counter()

        intent_logits, slot_logits = session.run(
            None,
            ort_inputs,
        )

        elapsed_ms = (
            time.perf_counter() - start
        ) * 1000.0

        inference_times_ms.append(
            elapsed_ms
        )

        predicted_intent_id = int(
            intent_logits.argmax(
                axis=-1
            )[0]
        )

        predicted_intent = id2intent[
            str(predicted_intent_id)
        ]

        first_piece_indexes = {}

        for token_index, word_id in enumerate(
            word_ids
        ):
            if word_id is None:
                continue

            if word_id in first_piece_indexes:
                continue

            if word_id >= len(words):
                continue

            first_piece_indexes[
                word_id
            ] = token_index

        ordered_word_ids = sorted(
            first_piece_indexes
        )

        word_logits_np = np.stack([
            slot_logits[
                0,
                first_piece_indexes[word_id],
                :
            ]
            for word_id in ordered_word_ids
        ])

        word_logits = torch.from_numpy(
            word_logits_np
        )

        allowed_ids = compatibility[
            predicted_intent
        ]["allowed_ids"]

        predicted_slot_ids = (
            constrained_viterbi(
                word_logits,
                id2slot,
                allowed_ids,
            )
        )

        predicted_slots = [
            id2slot[str(slot_id)]
            for slot_id
            in predicted_slot_ids
        ]

        if len(predicted_slots) < len(
            gold_slots
        ):
            predicted_slots.extend(
                ["O"] * (
                    len(gold_slots)
                    - len(predicted_slots)
                )
            )

        predicted_slots = predicted_slots[
            :len(gold_slots)
        ]

        intent_ok = (
            predicted_intent
            == gold_intent
        )

        slots_ok = (
            predicted_slots
            == gold_slots
        )

        total += 1

        if intent_ok:
            intent_correct += 1

        if slots_ok:
            slot_sentence_correct += 1

        if intent_ok and slots_ok:
            frame_correct += 1

        gold_sequences.append(
            gold_slots
        )

        pred_sequences.append(
            predicted_slots
        )

        if (
            (example_index + 1)
            % 100 == 0
        ):
            print(
                "Processed:",
                example_index + 1,
                "/",
                len(examples),
            )

    slot_f1 = f1_score(
        gold_sequences,
        pred_sequences,
        zero_division=0,
    )

    intent_accuracy = (
        intent_correct / total
    )

    slot_sentence_accuracy = (
        slot_sentence_correct / total
    )

    exact_frame_accuracy = (
        frame_correct / total
    )

    mean_latency = float(
        np.mean(inference_times_ms)
    )

    median_latency = percentile(
        inference_times_ms,
        50,
    )

    p95_latency = percentile(
        inference_times_ms,
        95,
    )

    print()
    print("=" * 76)
    print("RESULTS")
    print("=" * 76)

    print(
        f"Examples              : {total}"
    )

    print(
        f"Intent accuracy       : "
        f"{intent_accuracy:.4f} "
        f"({intent_accuracy * 100:.2f}%)"
    )

    print(
        f"Slot F1               : "
        f"{slot_f1:.4f} "
        f"({slot_f1 * 100:.2f}%)"
    )

    print(
        f"Slot sentence accuracy: "
        f"{slot_sentence_accuracy:.4f} "
        f"({slot_sentence_accuracy * 100:.2f}%)"
    )

    print(
        f"Exact frame accuracy  : "
        f"{exact_frame_accuracy:.4f} "
        f"({exact_frame_accuracy * 100:.2f}%)"
    )

    print()
    print("=" * 76)
    print("CPU ONNX LATENCY")
    print("=" * 76)

    print(
        f"Mean : {mean_latency:.2f} ms"
    )

    print(
        f"P50  : {median_latency:.2f} ms"
    )

    print(
        f"P95  : {p95_latency:.2f} ms"
    )

    result = {
        "model": str(model_path),
        "split": args.split,
        "examples": total,
        "intent_accuracy": intent_accuracy,
        "slot_f1": slot_f1,
        "slot_sentence_accuracy":
            slot_sentence_accuracy,
        "exact_frame_accuracy":
            exact_frame_accuracy,
        "latency_ms": {
            "mean": mean_latency,
            "p50": median_latency,
            "p95": p95_latency,
        },
    }

    output_name = (
        model_path.stem
        + "_"
        + args.split
        + "_evaluation.json"
    )

    output_path = (
        Path("/workspace/ml/results")
        / output_name
    )

    with open(
        output_path,
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            result,
            f,
            indent=2,
        )

    print()
    print(
        "Saved:",
        output_path,
    )


if __name__ == "__main__":
    main()
