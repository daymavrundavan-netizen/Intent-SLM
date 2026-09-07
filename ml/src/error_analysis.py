import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

import torch
from transformers import AutoTokenizer

from model import JointCommandSLM


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

    print("=" * 80)
    print("CDAC SLM ERROR ANALYSIS")
    print("=" * 80)
    print("Checkpoint :", checkpoint)
    print("Split      :", args.split)
    print("Device     :", device)
    print()

    model, config = JointCommandSLM.load_checkpoint(
        checkpoint,
        device=device,
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

    examples = load_jsonl(
        data_dir / f"{args.split}.jsonl"
    )

    total = 0

    correct_intents = 0
    correct_slots_exact = 0
    correct_frames = 0

    intent_confusions = Counter()

    slot_confusions = Counter()

    failures_by_intent = Counter()

    slot_errors_by_intent = defaultdict(Counter)

    false_negative_slots = Counter()
    false_positive_slots = Counter()
    wrong_type_slots = Counter()

    failure_examples = []

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
            return_tensors="pt",
        )

        word_ids = encoding.word_ids(
            batch_index=0
        )

        inputs = {
            key: value.to(device)
            for key, value in encoding.items()
        }

        intent_logits, slot_logits = model(
            input_ids=inputs["input_ids"],
            attention_mask=inputs["attention_mask"],
            token_type_ids=inputs.get(
                "token_type_ids"
            ),
        )

        intent_probs = torch.softmax(
            intent_logits,
            dim=-1,
        )[0]

        predicted_intent_id = int(
            intent_probs.argmax().item()
        )

        predicted_intent = id2intent[
            str(predicted_intent_id)
        ]

        token_slot_ids = (
            slot_logits
            .argmax(dim=-1)[0]
            .detach()
            .cpu()
            .tolist()
        )

        #
        # Convert WordPiece predictions back to
        # ONE prediction per original SNIPS word.
        #
        predicted_word_slots = {}

        for token_index, word_id in enumerate(
            word_ids
        ):

            if word_id is None:
                continue

            if word_id in predicted_word_slots:
                continue

            if word_id >= len(words):
                continue

            slot_id = token_slot_ids[
                token_index
            ]

            predicted_word_slots[
                word_id
            ] = id2slot[str(slot_id)]

        predictions = []

        for word_id in range(len(words)):

            #
            # Should not normally happen because
            # SNIPS commands are short, but protect
            # against truncation.
            #
            predictions.append(
                predicted_word_slots.get(
                    word_id,
                    "O",
                )
            )

        intent_ok = (
            predicted_intent
            == gold_intent
        )

        slots_ok = (
            predictions
            == gold_slots
        )

        frame_ok = (
            intent_ok
            and slots_ok
        )

        total += 1

        if intent_ok:
            correct_intents += 1
        else:
            intent_confusions[
                (
                    gold_intent,
                    predicted_intent,
                )
            ] += 1

        if slots_ok:
            correct_slots_exact += 1

        if frame_ok:
            correct_frames += 1

        if not frame_ok:
            failures_by_intent[
                gold_intent
            ] += 1

        mismatches = []

        for word, gold, pred in zip(
            words,
            gold_slots,
            predictions,
        ):

            if gold == pred:
                continue

            slot_confusions[
                (gold, pred)
            ] += 1

            slot_errors_by_intent[
                gold_intent
            ][
                (gold, pred)
            ] += 1

            #
            # Error category analysis
            #
            if (
                gold != "O"
                and pred == "O"
            ):
                false_negative_slots[
                    gold
                ] += 1

            elif (
                gold == "O"
                and pred != "O"
            ):
                false_positive_slots[
                    pred
                ] += 1

            elif (
                gold != "O"
                and pred != "O"
                and gold != pred
            ):
                wrong_type_slots[
                    (gold, pred)
                ] += 1

            mismatches.append({
                "word": word,
                "gold": gold,
                "pred": pred,
            })

        if not frame_ok:

            failure_examples.append({
                "index": example_index,
                "text": example["text"],

                "gold_intent":
                    gold_intent,

                "predicted_intent":
                    predicted_intent,

                "intent_confidence":
                    float(
                        intent_probs[
                            predicted_intent_id
                        ].item()
                    ),

                "intent_correct":
                    intent_ok,

                "slots_exact":
                    slots_ok,

                "slot_mismatches":
                    mismatches,

                "gold_slots":
                    gold_slots,

                "predicted_slots":
                    predictions,
            })

    intent_accuracy = (
        correct_intents / total
    )

    slot_sentence_accuracy = (
        correct_slots_exact / total
    )

    exact_frame_accuracy = (
        correct_frames / total
    )

    print("=" * 80)
    print("OVERALL")
    print("=" * 80)

    print(
        f"Examples                 : "
        f"{total}"
    )

    print(
        f"Intent accuracy          : "
        f"{intent_accuracy:.4f} "
        f"({intent_accuracy * 100:.2f}%)"
    )

    print(
        f"Slot sentence accuracy   : "
        f"{slot_sentence_accuracy:.4f} "
        f"({slot_sentence_accuracy * 100:.2f}%)"
    )

    print(
        f"Exact frame accuracy     : "
        f"{exact_frame_accuracy:.4f} "
        f"({exact_frame_accuracy * 100:.2f}%)"
    )

    print(
        f"Failed frames            : "
        f"{total - correct_frames}"
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
            predicted,
        ), count in intent_confusions.most_common(
            20
        ):
            print(
                f"{gold:28s}"
                f" -> "
                f"{predicted:28s}"
                f" : {count}"
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
    print("TOP 30 SLOT CONFUSIONS")
    print("=" * 80)

    for (
        gold,
        predicted,
    ), count in slot_confusions.most_common(
        30
    ):
        print(
            f"{gold:35s}"
            f" -> "
            f"{predicted:35s}"
            f" : {count}"
        )

    print()

    print("=" * 80)
    print("TOP MISSED SLOTS (GOLD SLOT -> O)")
    print("=" * 80)

    for label, count in (
        false_negative_slots.most_common(
            20
        )
    ):
        print(
            f"{label:40s}: {count}"
        )

    print()

    print("=" * 80)
    print("TOP FALSE POSITIVE SLOTS (O -> SLOT)")
    print("=" * 80)

    for label, count in (
        false_positive_slots.most_common(
            20
        )
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
        predicted,
    ), count in (
        wrong_type_slots.most_common(
            20
        )
    ):
        print(
            f"{gold:35s}"
            f" -> "
            f"{predicted:35s}"
            f" : {count}"
        )

    print()

    print("=" * 80)
    print("SAMPLE FAILED COMMANDS")
    print("=" * 80)

    for failure in failure_examples[:20]:

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

        if failure[
            "slot_mismatches"
        ]:

            for mismatch in failure[
                "slot_mismatches"
            ]:

                print(
                    "  ",
                    repr(
                        mismatch["word"]
                    ),
                    ":",
                    mismatch["gold"],
                    "->",
                    mismatch["pred"],
                )

    #
    # Save detailed JSON output for later.
    #
    output_file = (
        output_dir
        / (
            checkpoint.name
            + "_"
            + args.split
            + "_errors.json"
        )
    )

    summary_file = (
        output_dir
        / (
            checkpoint.name
            + "_"
            + args.split
            + "_summary.json"
        )
    )

    with open(
        output_file,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            failure_examples,
            f,
            indent=2,
            ensure_ascii=False,
        )

    summary = {
        "checkpoint":
            str(checkpoint),

        "split":
            args.split,

        "examples":
            total,

        "intent_accuracy":
            intent_accuracy,

        "slot_sentence_accuracy":
            slot_sentence_accuracy,

        "exact_frame_accuracy":
            exact_frame_accuracy,

        "failed_frames":
            total - correct_frames,

        "failures_by_intent":
            dict(
                failures_by_intent
            ),

        "intent_confusions": [
            {
                "gold": gold,
                "predicted": predicted,
                "count": count,
            }
            for (
                gold,
                predicted,
            ), count
            in intent_confusions.most_common()
        ],

        "top_slot_confusions": [
            {
                "gold": gold,
                "predicted": predicted,
                "count": count,
            }
            for (
                gold,
                predicted,
            ), count
            in slot_confusions.most_common(
                50
            )
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
    print("=" * 80)
    print("FILES SAVED")
    print("=" * 80)

    print(
        "Detailed errors:",
        output_file,
    )

    print(
        "Summary        :",
        summary_file,
    )


if __name__ == "__main__":
    main()
