import argparse
import json
import random
import shutil
from collections import Counter, defaultdict
from pathlib import Path


TARGET_TYPES = {
    # Music / playlist confusions
    "album",
    "track",
    "playlist",
    "entity_name",
    "artist",
    "music_item",

    # Creative-work confusions
    "movie_name",
    "object_name",
    "object_select",
    "movie_type",

    # Restaurant confusions
    "cuisine",
    "served_dish",
    "restaurant_name",
    "restaurant_type",

    # Geographic confusions
    "city",
    "poi",
    "country",
    "state",
    "spatial_relation",
}


HARD_FAMILIES = [
    {
        "album",
        "track",
        "playlist",
        "entity_name",
        "artist",
    },
    {
        "movie_name",
        "object_name",
    },
    {
        "cuisine",
        "served_dish",
    },
]


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_jsonl(path):
    rows = []

    with open(path, encoding="utf-8") as f:
        for line in f:
            rows.append(json.loads(line))

    return rows


def extract_spans(tokens, labels):
    """
    Returns:
        [
            {
                "start": int,
                "end": int,
                "type": str,
                "tokens": tuple(...)
            }
        ]
    """

    spans = []

    i = 0

    while i < len(labels):
        label = labels[i]

        if not label.startswith("B-"):
            i += 1
            continue

        slot_type = label[2:]

        j = i + 1

        while (
            j < len(labels)
            and labels[j] == f"I-{slot_type}"
        ):
            j += 1

        spans.append({
            "start": i,
            "end": j,
            "type": slot_type,
            "tokens": tuple(tokens[i:j]),
        })

        i = j

    return spans


def labels_for_span(slot_type, length, slot2id):
    if length <= 0:
        return None

    b_label = f"B-{slot_type}"

    if b_label not in slot2id:
        return None

    if length == 1:
        return [b_label]

    i_label = f"I-{slot_type}"

    if i_label not in slot2id:
        return None

    return (
        [b_label]
        + [i_label] * (length - 1)
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--source-dir",
        default="/workspace/ml/data/processed",
    )

    parser.add_argument(
        "--output-dir",
        default="/workspace/ml/data/processed_v4",
    )

    parser.add_argument(
        "--max-augmented",
        type=int,
        default=7000,
    )

    parser.add_argument(
        "--hard-prob",
        type=float,
        default=0.45,
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=1337,
    )

    args = parser.parse_args()

    rng = random.Random(args.seed)

    source_dir = Path(args.source_dir)
    output_dir = Path(args.output_dir)

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    train = load_jsonl(
        source_dir / "train.jsonl"
    )

    slot2id = load_json(
        source_dir / "slot2id.json"
    )

    #
    # Donor pools.
    #
    # same_type_pool:
    #   (intent, slot_type) -> set(values)
    #
    same_type_pool = defaultdict(set)

    #
    # hard_pool:
    #   (intent, family_index)
    #       -> [(source_slot_type, value)]
    #
    hard_pool = defaultdict(set)

    type_to_family = {}

    for family_index, family in enumerate(
        HARD_FAMILIES
    ):
        for slot_type in family:
            type_to_family[
                slot_type
            ] = family_index

    for example in train:
        intent = example["intent"]

        spans = extract_spans(
            example["tokens"],
            example["slots"],
        )

        for span in spans:
            slot_type = span["type"]
            value = span["tokens"]

            if slot_type not in TARGET_TYPES:
                continue

            same_type_pool[
                (intent, slot_type)
            ].add(value)

            if slot_type in type_to_family:
                family_index = type_to_family[
                    slot_type
                ]

                hard_pool[
                    (intent, family_index)
                ].add(
                    (slot_type, value)
                )

    #
    # Convert sets to deterministic lists.
    #
    same_type_pool = {
        key: sorted(values)
        for key, values
        in same_type_pool.items()
    }

    hard_pool = {
        key: sorted(values)
        for key, values
        in hard_pool.items()
    }

    #
    # Shuffle examples so augmentation is not biased
    # toward early examples in the file.
    #
    candidate_indexes = list(
        range(len(train))
    )

    rng.shuffle(candidate_indexes)

    augmented = []

    seen = {
        (
            example["intent"],
            tuple(example["tokens"]),
            tuple(example["slots"]),
        )
        for example in train
    }

    mode_counter = Counter()
    destination_counter = Counter()

    for index in candidate_indexes:

        if len(augmented) >= args.max_augmented:
            break

        example = train[index]

        intent = example["intent"]

        spans = [
            span
            for span in extract_spans(
                example["tokens"],
                example["slots"],
            )
            if span["type"] in TARGET_TYPES
        ]

        if not spans:
            continue

        rng.shuffle(spans)

        replacement = None

        for span in spans:
            destination_type = span["type"]
            original_value = span["tokens"]

            donor_value = None
            augmentation_mode = None

            #
            # HARD augmentation:
            #
            # For the highest-confusion semantic families,
            # sometimes inject a value normally observed
            # under another slot type.
            #
            # Example:
            #   an observed track title may be inserted into
            #   an album context but receives album labels.
            #
            # This forces the model to use linguistic context.
            #
            use_hard = (
                destination_type in type_to_family
                and rng.random() < args.hard_prob
            )

            if use_hard:
                family_index = type_to_family[
                    destination_type
                ]

                candidates = [
                    value
                    for source_type, value
                    in hard_pool.get(
                        (intent, family_index),
                        [],
                    )
                    if (
                        source_type
                        != destination_type
                        and value
                        != original_value
                    )
                ]

                rng.shuffle(candidates)

                for value in candidates[:30]:
                    new_labels = labels_for_span(
                        destination_type,
                        len(value),
                        slot2id,
                    )

                    if new_labels is not None:
                        donor_value = value
                        augmentation_mode = "hard"
                        break

            #
            # SAFE fallback:
            # Same intent + same slot type.
            #
            if donor_value is None:
                candidates = [
                    value
                    for value
                    in same_type_pool.get(
                        (
                            intent,
                            destination_type,
                        ),
                        [],
                    )
                    if value != original_value
                ]

                rng.shuffle(candidates)

                for value in candidates[:30]:
                    new_labels = labels_for_span(
                        destination_type,
                        len(value),
                        slot2id,
                    )

                    if new_labels is not None:
                        donor_value = value
                        augmentation_mode = "same_type"
                        break

            if donor_value is None:
                continue

            replacement = (
                span,
                donor_value,
                augmentation_mode,
            )

            break

        if replacement is None:
            continue

        span, donor_value, augmentation_mode = (
            replacement
        )

        start = span["start"]
        end = span["end"]
        slot_type = span["type"]

        replacement_labels = labels_for_span(
            slot_type,
            len(donor_value),
            slot2id,
        )

        if replacement_labels is None:
            continue

        new_tokens = (
            example["tokens"][:start]
            + list(donor_value)
            + example["tokens"][end:]
        )

        new_slots = (
            example["slots"][:start]
            + replacement_labels
            + example["slots"][end:]
        )

        if len(new_tokens) != len(new_slots):
            raise RuntimeError(
                "Token/slot length mismatch"
            )

        new_example = {
            "text": " ".join(new_tokens),
            "tokens": new_tokens,
            "slots": new_slots,
            "intent": intent,
        }

        signature = (
            intent,
            tuple(new_tokens),
            tuple(new_slots),
        )

        if signature in seen:
            continue

        seen.add(signature)

        augmented.append(new_example)

        mode_counter[
            augmentation_mode
        ] += 1

        destination_counter[
            slot_type
        ] += 1

    combined = (
        train
        + augmented
    )

    rng.shuffle(combined)

    with open(
        output_dir / "train.jsonl",
        "w",
        encoding="utf-8",
    ) as f:
        for example in combined:
            f.write(
                json.dumps(
                    example,
                    ensure_ascii=False,
                )
                + "\n"
            )

    #
    # Validation and test remain EXACTLY untouched.
    #
    for filename in [
        "valid.jsonl",
        "test.jsonl",
        "intent2id.json",
        "id2intent.json",
        "slot2id.json",
        "id2slot.json",
    ]:
        shutil.copy2(
            source_dir / filename,
            output_dir / filename,
        )

    report = {
        "original_train_examples":
            len(train),

        "augmented_examples":
            len(augmented),

        "combined_train_examples":
            len(combined),

        "augmentation_modes":
            dict(mode_counter),

        "augmented_destination_slots":
            dict(
                destination_counter.most_common()
            ),

        "seed":
            args.seed,

        "hard_probability":
            args.hard_prob,
    }

    with open(
        output_dir
        / "augmentation_report.json",
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            report,
            f,
            indent=2,
        )

    print("=" * 72)
    print("CDAC V4 TARGETED AUGMENTATION")
    print("=" * 72)

    print(
        "Original examples :",
        len(train),
    )

    print(
        "Augmented examples:",
        len(augmented),
    )

    print(
        "Combined examples :",
        len(combined),
    )

    print()

    print("Augmentation modes:")

    for key, value in (
        mode_counter.most_common()
    ):
        print(
            f"  {key:20s}: {value}"
        )

    print()

    print("Top destination slot types:")

    for key, value in (
        destination_counter.most_common(20)
    ):
        print(
            f"  {key:25s}: {value}"
        )

    print()

    print(
        "Output:",
        output_dir,
    )


if __name__ == "__main__":
    main()
