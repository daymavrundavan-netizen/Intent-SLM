import json
from pathlib import Path
from collections import Counter

ROOT = Path("/workspace")
RAW = ROOT / "ml/data/raw/SlotGated-SLU/data/snips"
OUT = ROOT / "ml/data/processed"

OUT.mkdir(parents=True, exist_ok=True)

splits = ["train", "valid", "test"]

all_intents = set()
all_slots = set()

report = {}

for split in splits:
    split_dir = RAW / split

    with open(split_dir / "seq.in", encoding="utf-8") as f:
        sentences = [x.rstrip("\n") for x in f]

    with open(split_dir / "seq.out", encoding="utf-8") as f:
        slots = [x.rstrip("\n") for x in f]

    with open(split_dir / "label", encoding="utf-8") as f:
        intents = [x.strip() for x in f]

    assert len(sentences) == len(slots) == len(intents), \
        f"{split}: file length mismatch"

    records = []
    intent_counter = Counter()
    slot_counter = Counter()

    for i, (sentence, slot_line, intent) in enumerate(
        zip(sentences, slots, intents)
    ):
        tokens = sentence.split()
        slot_labels = slot_line.split()

        if len(tokens) != len(slot_labels):
            raise ValueError(
                f"{split} line {i}: "
                f"{len(tokens)} tokens but {len(slot_labels)} slots\n"
                f"{sentence}\n{slot_line}"
            )

        all_intents.add(intent)
        all_slots.update(slot_labels)

        intent_counter[intent] += 1
        slot_counter.update(slot_labels)

        records.append({
            "text": sentence,
            "tokens": tokens,
            "slots": slot_labels,
            "intent": intent,
        })

    with open(OUT / f"{split}.jsonl", "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    report[split] = {
        "examples": len(records),
        "intent_counts": dict(intent_counter),
        "slot_counts": dict(slot_counter),
    }

intent_labels = sorted(all_intents)

slot_labels = ["O"] + sorted(
    label for label in all_slots if label != "O"
)

intent2id = {label: i for i, label in enumerate(intent_labels)}
slot2id = {label: i for i, label in enumerate(slot_labels)}

with open(OUT / "intent2id.json", "w") as f:
    json.dump(intent2id, f, indent=2)

with open(OUT / "slot2id.json", "w") as f:
    json.dump(slot2id, f, indent=2)

with open(OUT / "id2intent.json", "w") as f:
    json.dump(
        {str(v): k for k, v in intent2id.items()},
        f,
        indent=2
    )

with open(OUT / "id2slot.json", "w") as f:
    json.dump(
        {str(v): k for k, v in slot2id.items()},
        f,
        indent=2
    )

report["num_intents"] = len(intent_labels)
report["num_slot_labels"] = len(slot_labels)
report["intents"] = intent_labels
report["slot_labels"] = slot_labels

with open(OUT / "dataset_report.json", "w") as f:
    json.dump(report, f, indent=2)

print("=" * 70)
print("SNIPS PREPARATION COMPLETE")
print("=" * 70)
print("Intents:", len(intent_labels))
print("Slot labels:", len(slot_labels))

for split in splits:
    print(f"{split:>5}: {report[split]['examples']} examples")

print("\nIntents:")
for label in intent_labels:
    print(" -", label)

print("\nOutput:", OUT)
