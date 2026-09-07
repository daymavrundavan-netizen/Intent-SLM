import argparse
import json
from pathlib import Path

import torch
from torch.utils.data import DataLoader
from transformers import AutoTokenizer
from seqeval.metrics import f1_score

from dataset import SnipsDataset
from model import JointCommandSLM


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


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
        choices=["train", "valid", "test"],
        default="valid",
    )

    parser.add_argument(
        "--batch-size",
        type=int,
        default=32,
    )

    args = parser.parse_args()

    checkpoint = Path(args.checkpoint)
    data_dir = Path(args.data_dir)

    device = torch.device(
        "cuda" if torch.cuda.is_available()
        else "cpu"
    )

    model, config = \
        JointCommandSLM.load_checkpoint(
            checkpoint,
            device=device,
        )

    model.eval()

    tokenizer = AutoTokenizer.from_pretrained(
        checkpoint / "tokenizer",
        use_fast=True,
    )

    intent2id = load_json(
        checkpoint / "intent2id.json"
    )

    slot2id = load_json(
        checkpoint / "slot2id.json"
    )

    id2slot = load_json(
        checkpoint / "id2slot.json"
    )

    dataset = SnipsDataset(
        data_dir / f"{args.split}.jsonl",
        tokenizer,
        intent2id,
        slot2id,
        config["max_length"],
    )

    loader = DataLoader(
        dataset,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=2,
    )

    total = 0
    correct_intents = 0
    exact = 0

    pred_sequences = []
    gold_sequences = []

    for batch in loader:
        batch = {
            k: v.to(device)
            for k, v in batch.items()
        }

        intent_logits, slot_logits = model(
            input_ids=batch["input_ids"],
            attention_mask=batch["attention_mask"],
            token_type_ids=batch.get(
                "token_type_ids"
            ),
        )

        intent_pred = \
            intent_logits.argmax(-1)

        slot_pred = \
            slot_logits.argmax(-1)

        for i in range(intent_pred.size(0)):
            intent_ok = (
                intent_pred[i].item()
                == batch["intent_labels"][i].item()
            )

            correct_intents += int(intent_ok)
            total += 1

            pseq = []
            gseq = []

            slot_ok = True

            for j in range(slot_pred.size(1)):
                gold = \
                    batch["slot_labels"][i, j].item()

                if gold == -100:
                    continue

                pred = slot_pred[i, j].item()

                pseq.append(id2slot[str(pred)])
                gseq.append(id2slot[str(gold)])

                if pred != gold:
                    slot_ok = False

            pred_sequences.append(pseq)
            gold_sequences.append(gseq)

            if intent_ok and slot_ok:
                exact += 1

    results = {
        "split": args.split,
        "examples": total,
        "intent_accuracy":
            correct_intents / total,
        "slot_f1":
            f1_score(
                gold_sequences,
                pred_sequences,
                zero_division=0,
            ),
        "exact_frame_accuracy":
            exact / total,
    }

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
