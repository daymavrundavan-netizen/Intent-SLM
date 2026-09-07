import argparse
import json
from pathlib import Path

import torch
from tqdm import tqdm
from transformers import AutoTokenizer
from seqeval.metrics import f1_score

from model import JointCommandSLM
from constrained_decoder import (
    apply_intent_mask,
    constrained_viterbi,
)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_jsonl(path):
    examples = []

    with open(path, encoding="utf-8") as f:
        for line in f:
            examples.append(
                json.loads(line)
            )

    return examples


class Metrics:
    def __init__(self):
        self.total = 0
        self.intent_correct = 0
        self.slot_sentence_correct = 0
        self.frame_correct = 0

        self.gold_sequences = []
        self.pred_sequences = []

    def update(
        self,
        gold_intent,
        predicted_intent,
        gold_slots,
        predicted_slots,
    ):
        self.total += 1

        intent_ok = (
            gold_intent
            == predicted_intent
        )

        slots_ok = (
            gold_slots
            == predicted_slots
        )

        if intent_ok:
            self.intent_correct += 1

        if slots_ok:
            self.slot_sentence_correct += 1

        if intent_ok and slots_ok:
            self.frame_correct += 1

        self.gold_sequences.append(
            gold_slots
        )

        self.pred_sequences.append(
            predicted_slots
        )

    def results(self):
        return {
            "intent_accuracy":
                self.intent_correct
                / self.total,

            "slot_f1":
                f1_score(
                    self.gold_sequences,
                    self.pred_sequences,
                    zero_division=0,
                ),

            "slot_sentence_accuracy":
                self.slot_sentence_correct
                / self.total,

            "exact_frame_accuracy":
                self.frame_correct
                / self.total,
        }


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

    args = parser.parse_args()

    checkpoint = Path(args.checkpoint)
    data_dir = Path(args.data_dir)

    device = torch.device(
        "cuda"
        if torch.cuda.is_available()
        else "cpu"
    )

    print("=" * 76)
    print("CDAC SLM V2 DECODER EVALUATION")
    print("=" * 76)
    print("Checkpoint:", checkpoint)
    print("Split     :", args.split)
    print("Device    :", device)
    print()

    model, config = (
        JointCommandSLM.load_checkpoint(
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
        checkpoint
        / "intent_slot_compat.json"
    )

    examples = load_jsonl(
        data_dir / f"{args.split}.jsonl"
    )

    metrics = {
        "raw":
            Metrics(),

        "intent_mask":
            Metrics(),

        "intent_mask_bio":
            Metrics(),

        "oracle_intent_bio":
            Metrics(),
    }

    for example in tqdm(
        examples,
        desc="Evaluating",
    ):

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
            attention_mask=inputs[
                "attention_mask"
            ],
            token_type_ids=inputs.get(
                "token_type_ids"
            ),
        )

        predicted_intent_id = int(
            intent_logits
            .argmax(dim=-1)[0]
            .item()
        )

        predicted_intent = (
            id2intent[
                str(predicted_intent_id)
            ]
        )

        #
        # Locate the FIRST WordPiece for
        # every original word.
        #
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
            for word_id
            in ordered_word_ids
        ])

        #
        # RAW
        #
        raw_ids = (
            word_logits.argmax(dim=-1)
            .detach()
            .cpu()
            .tolist()
        )

        raw_labels = [
            id2slot[str(slot_id)]
            for slot_id in raw_ids
        ]

        #
        # Intent-aware mask.
        #
        predicted_allowed_ids = (
            compatibility[
                predicted_intent
            ]["allowed_ids"]
        )

        masked_logits = (
            apply_intent_mask(
                word_logits.detach().cpu(),
                predicted_allowed_ids,
            )
        )

        masked_ids = (
            masked_logits
            .argmax(dim=-1)
            .tolist()
        )

        masked_labels = [
            id2slot[str(slot_id)]
            for slot_id in masked_ids
        ]

        #
        # Intent mask + constrained BIO.
        #
        constrained_ids = (
            constrained_viterbi(
                word_logits,
                id2slot,
                predicted_allowed_ids,
            )
        )

        constrained_labels = [
            id2slot[str(slot_id)]
            for slot_id
            in constrained_ids
        ]

        #
        # ORACLE intent.
        #
        # NOT deployable.
        # Diagnostic only.
        #
        oracle_allowed_ids = (
            compatibility[
                gold_intent
            ]["allowed_ids"]
        )

        oracle_ids = (
            constrained_viterbi(
                word_logits,
                id2slot,
                oracle_allowed_ids,
            )
        )

        oracle_labels = [
            id2slot[str(slot_id)]
            for slot_id in oracle_ids
        ]

        #
        # Protect against theoretical
        # truncation.
        #
        def fill_to_length(labels):

            labels = list(labels)

            if len(labels) < len(gold_slots):
                labels.extend(
                    ["O"]
                    * (
                        len(gold_slots)
                        - len(labels)
                    )
                )

            return labels[
                :len(gold_slots)
            ]

        raw_labels = fill_to_length(
            raw_labels
        )

        masked_labels = fill_to_length(
            masked_labels
        )

        constrained_labels = fill_to_length(
            constrained_labels
        )

        oracle_labels = fill_to_length(
            oracle_labels
        )

        metrics["raw"].update(
            gold_intent,
            predicted_intent,
            gold_slots,
            raw_labels,
        )

        metrics["intent_mask"].update(
            gold_intent,
            predicted_intent,
            gold_slots,
            masked_labels,
        )

        metrics["intent_mask_bio"].update(
            gold_intent,
            predicted_intent,
            gold_slots,
            constrained_labels,
        )

        metrics["oracle_intent_bio"].update(
            gold_intent,
            gold_intent,
            gold_slots,
            oracle_labels,
        )

    results = {
        key: value.results()
        for key, value
        in metrics.items()
    }

    print()
    print("=" * 76)
    print("RESULTS")
    print("=" * 76)

    print(
        f"{'METHOD':25s}"
        f"{'INTENT':>12s}"
        f"{'SLOT F1':>12s}"
        f"{'SLOT SENT':>12s}"
        f"{'EXACT':>12s}"
    )

    print("-" * 76)

    names = {
        "raw":
            "Raw baseline",

        "intent_mask":
            "Intent mask",

        "intent_mask_bio":
            "Mask + BIO",

        "oracle_intent_bio":
            "Oracle intent + BIO",
    }

    for key in [
        "raw",
        "intent_mask",
        "intent_mask_bio",
        "oracle_intent_bio",
    ]:

        r = results[key]

        print(
            f"{names[key]:25s}"
            f"{r['intent_accuracy'] * 100:11.2f}%"
            f"{r['slot_f1'] * 100:11.2f}%"
            f"{r['slot_sentence_accuracy'] * 100:11.2f}%"
            f"{r['exact_frame_accuracy'] * 100:11.2f}%"
        )

    output = (
        "/workspace/ml/results/"
        "v2_decoder_validation.json"
    )

    with open(
        output,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            results,
            f,
            indent=2,
        )

    print()
    print("Saved:", output)


if __name__ == "__main__":
    main()
