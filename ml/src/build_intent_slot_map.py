import argparse
import json
from collections import defaultdict
from pathlib import Path


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--data-dir",
        default="/workspace/ml/data/processed",
    )

    parser.add_argument(
        "--checkpoint",
        required=True,
    )

    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    checkpoint = Path(args.checkpoint)

    slot2id = load_json(
        checkpoint / "slot2id.json"
    )

    # Collect BASE slot types used by each intent.
    # Example:
    # B-city / I-city -> city
    intent_to_types = defaultdict(set)

    train_file = data_dir / "train.jsonl"

    with open(train_file, encoding="utf-8") as f:
        for line in f:
            example = json.loads(line)

            intent = example["intent"]

            for label in example["slots"]:

                if label == "O":
                    continue

                if "-" not in label:
                    continue

                _, slot_type = label.split("-", 1)

                intent_to_types[intent].add(
                    slot_type
                )

    compatibility = {}

    for intent, slot_types in sorted(
        intent_to_types.items()
    ):

        allowed_labels = ["O"]

        for label in slot2id:

            if label == "O":
                continue

            if "-" not in label:
                continue

            _, slot_type = label.split("-", 1)

            if slot_type in slot_types:
                allowed_labels.append(label)

        allowed_ids = sorted(
            slot2id[label]
            for label in allowed_labels
        )

        compatibility[intent] = {
            "slot_types": sorted(slot_types),
            "allowed_labels": sorted(
                allowed_labels
            ),
            "allowed_ids": allowed_ids,
        }

    output = (
        checkpoint / "intent_slot_compat.json"
    )

    with open(
        output,
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            compatibility,
            f,
            indent=2,
            ensure_ascii=False,
        )

    print("=" * 70)
    print("INTENT-SLOT COMPATIBILITY")
    print("=" * 70)

    for intent, info in compatibility.items():

        print()
        print(intent)
        print(
            "  slot types:",
            len(info["slot_types"]),
        )

        print(
            "  labels    :",
            len(info["allowed_labels"]),
        )

        print(
            "  ",
            ", ".join(info["slot_types"]),
        )

    print()
    print("Saved:", output)


if __name__ == "__main__":
    main()
