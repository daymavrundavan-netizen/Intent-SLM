import argparse
import json
from collections import Counter
from pathlib import Path

import torch
from transformers import AutoTokenizer

from model_v3 import IntentConditionedCommandSLM
from constrained_decoder import constrained_viterbi


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            rows.append(json.loads(line))
    return rows


@torch.no_grad()
def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("checkpoint")

    parser.add_argument(
        "--data-dir",
        default="/workspace/ml/data/processed",
    )

    parser.add_argument(
        "--split",
        choices=["train", "valid"],
        default="valid",
    )

    parser.add_argument(
        "--output-dir",
        default="/workspace/ml/results/error_analysis",
    )

    args = parser.parse_args()

    checkpoint = Path(args.checkpoint)
    data_dir = Path(args.data_dir)
    output_dir = Path(args.output_dir)

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    device = torch.device(
        "cuda"
        if torch.cuda.is_available()
        else "cpu"
    )

    model, config = (
        IntentConditionedCommandSLM.load_checkpoint(
            checkpoint,
            device=device,
        )
    )

    model.eval()

    tokenizer = AutoTokenizer.from_pretrained(
        checkpoint / "tokenizer",
        use_fast=True,
    )

    id2intent = load_json(
        checkpoint / "id2intent.json"
    )

    id2slot = load_json(
        checkpoint / "id2slot.json"
    )

    compatibility = load_json(
        checkpoint / "intent_slot_compat.json"
    )

    examples = load_jsonl(
        data_dir / f"{args.split}.jsonl"
    )

    total = 0
    intent_correct = 0
    exact_correct = 0

    failures_by_intent = Counter()
    intent_confusions = Counter()
    slot_confusions = Counter()

    false_negatives = Counter()
    false_positives = Counter()
    wrong_types = Counter()

    failures = []

    for index, example in enumerate(examples):

        words = example["tokens"]
        gold_slots = example["slots"]
        gold_intent = example["intent"]

        encoding = tokenizer(
            words,
            is_split_into_words=True,
            truncation=True,
            padding="max_length",
            max_length=config["max_length"],
            return_tensors="pt",
        )

        word_ids = encoding.word_ids(
            batch_index=0
        )

        inputs = {
            key: value.to(device)
            for key, value
            in encoding.items()
        }

        intent_logits, slot_logits = model(
            input_ids=inputs["input_ids"],
            attention_mask=inputs["attention_mask"],
            token_type_ids=inputs.get(
                "token_type_ids"
            ),
        )

        pred_intent_id = int(
            intent_logits.argmax(-1)[0].item()
        )

        pred_intent = id2intent[
            str(pred_intent_id)
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

        word_logits = torch.stack([
            slot_logits[
                0,
                first_piece_indexes[word_id],
                :
            ]
            for word_id in ordered_word_ids
        ])

        allowed_ids = compatibility[
            pred_intent
        ]["allowed_ids"]

        pred_ids = constrained_viterbi(
            word_logits,
            id2slot,
            allowed_ids,
        )

        pred_slots = [
            id2slot[str(slot_id)]
            for slot_id in pred_ids
        ]

        if len(pred_slots) < len(gold_slots):
            pred_slots.extend(
                ["O"] * (
                    len(gold_slots)
                    - len(pred_slots)
                )
            )

        pred_slots = pred_slots[
            :len(gold_slots)
        ]

        total += 1

        intent_ok = (
            pred_intent == gold_intent
        )

        slots_ok = (
            pred_slots == gold_slots
        )

        if intent_ok:
            intent_correct += 1
        else:
            intent_confusions[
                (gold_intent, pred_intent)
            ] += 1

        if intent_ok and slots_ok:
            exact_correct += 1
            continue

        failures_by_intent[
            gold_intent
        ] += 1

        mismatches = []

        for word, gold, pred in zip(
            words,
            gold_slots,
            pred_slots,
        ):

            if gold == pred:
                continue

            slot_confusions[
                (gold, pred)
            ] += 1

            if gold != "O" and pred == "O":
                false_negatives[
                    gold
                ] += 1

            elif gold == "O" and pred != "O":
                false_positives[
                    pred
                ] += 1

            else:
                wrong_types[
                    (gold, pred)
                ] += 1

            mismatches.append({
                "word": word,
                "gold": gold,
                "pred": pred,
            })

        failures.append({
            "index": index,
            "text": example["text"],
            "gold_intent": gold_intent,
            "predicted_intent": pred_intent,
            "slot_mismatches": mismatches,
            "gold_slots": gold_slots,
            "predicted_slots": pred_slots,
        })

    print("=" * 80)
    print("V3 + MASK + BIO ERROR ANALYSIS")
    print("=" * 80)

    print(
        f"Examples        : {total}"
    )

    print(
        f"Intent accuracy : "
        f"{intent_correct / total:.4f} "
        f"({100 * intent_correct / total:.2f}%)"
    )

    print(
        f"Exact frame     : "
        f"{exact_correct / total:.4f} "
        f"({100 * exact_correct / total:.2f}%)"
    )

    print(
        f"Failed frames   : "
        f"{total - exact_correct}"
    )

    print()

    print("=" * 80)
    print("FAILURES BY TRUE INTENT")
    print("=" * 80)

    for intent, count in (
        failures_by_intent.most_common()
    ):
        print(
            f"{intent:28s}: {count}"
        )

    print()

    print("=" * 80)
    print("INTENT CONFUSIONS")
    print("=" * 80)

    if not intent_confusions:
        print("None")
    else:
        for (
            gold,
            pred,
        ), count in intent_confusions.most_common():

            print(
                f"{gold:28s}"
                f" -> "
                f"{pred:28s}"
                f" : {count}"
            )

    print()

    print("=" * 80)
    print("TOP SLOT CONFUSIONS")
    print("=" * 80)

    for (
        gold,
        pred,
    ), count in slot_confusions.most_common(40):

        print(
            f"{gold:35s}"
            f" -> "
            f"{pred:35s}"
            f" : {count}"
        )

    print()

    print("=" * 80)
    print("TOP MISSED SLOTS")
    print("=" * 80)

    for label, count in (
        false_negatives.most_common(25)
    ):
        print(
            f"{label:40s}: {count}"
        )

    print()

    print("=" * 80)
    print("TOP FALSE POSITIVE SLOTS")
    print("=" * 80)

    for label, count in (
        false_positives.most_common(25)
    ):
        print(
            f"{label:40s}: {count}"
        )

    print()

    print("=" * 80)
    print("TOP WRONG SLOT TYPES")
    print("=" * 80)

    for (
        gold,
        pred,
    ), count in wrong_types.most_common(30):

        print(
            f"{gold:35s}"
            f" -> "
            f"{pred:35s}"
            f" : {count}"
        )

    print()

    print("=" * 80)
    print("FIRST 25 FAILED COMMANDS")
    print("=" * 80)

    for failure in failures[:25]:

        print()
        print(
            "TEXT:",
            failure["text"]
        )

        print(
            "INTENT:",
            failure["gold_intent"],
            "->",
            failure["predicted_intent"],
        )

        for mismatch in failure[
            "slot_mismatches"
        ]:

            print(
                " ",
                repr(mismatch["word"]),
                ":",
                mismatch["gold"],
                "->",
                mismatch["pred"],
            )

    detail_file = (
        output_dir
        / "v3_decoder_valid_errors.json"
    )

    summary_file = (
        output_dir
        / "v3_decoder_valid_summary.json"
    )

    with open(
        detail_file,
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            failures,
            f,
            indent=2,
            ensure_ascii=False,
        )

    summary = {
        "examples": total,
        "intent_accuracy":
            intent_correct / total,
        "exact_frame_accuracy":
            exact_correct / total,
        "failed_frames":
            total - exact_correct,
        "failures_by_intent":
            dict(failures_by_intent),
        "top_slot_confusions": [
            {
                "gold": gold,
                "pred": pred,
                "count": count,
            }
            for (
                gold,
                pred,
            ), count
            in slot_confusions.most_common(50)
        ],
    }

    with open(
        summary_file,
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            summary,
            f,
            indent=2,
            ensure_ascii=False,
        )

    print()
    print("Saved:")
    print(detail_file)
    print(summary_file)


if __name__ == "__main__":
    main()
