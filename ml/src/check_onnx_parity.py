import argparse
from pathlib import Path

import numpy as np
import onnxruntime as ort
import torch
from transformers import AutoTokenizer

from model_v3 import IntentConditionedCommandSLM


TEST_COMMANDS = [
    "play a song by adele",
    "add hotel california to my road trip playlist",
    "what is the weather in mumbai tomorrow",
    "book a table for four in new york tonight",
    "rate this book five out of five",
    "find the movie inception",
    "show me screenings for dune tonight",
]


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--checkpoint",
        required=True,
    )

    parser.add_argument(
        "--onnx",
        required=True,
    )

    args = parser.parse_args()

    checkpoint = Path(args.checkpoint)

    model, config = (
        IntentConditionedCommandSLM.load_checkpoint(
            checkpoint,
            device="cpu",
        )
    )

    model.eval()

    tokenizer = AutoTokenizer.from_pretrained(
        checkpoint / "tokenizer",
        use_fast=True,
    )

    session = ort.InferenceSession(
        args.onnx,
        providers=[
            "CPUExecutionProvider"
        ],
    )

    maximum_intent_error = 0.0
    maximum_slot_error = 0.0

    intent_matches = 0
    slot_argmax_matches = 0
    slot_argmax_total = 0

    for text in TEST_COMMANDS:

        encoded = tokenizer(
            text,
            truncation=True,
            padding="max_length",
            max_length=config[
                "max_length"
            ],
            return_tensors="pt",
        )

        token_type_ids = encoded.get(
            "token_type_ids"
        )

        if token_type_ids is None:
            token_type_ids = torch.zeros_like(
                encoded["input_ids"]
            )

        with torch.no_grad():

            pt_intent, pt_slots = model(
                input_ids=encoded[
                    "input_ids"
                ],
                attention_mask=encoded[
                    "attention_mask"
                ],
                token_type_ids=(
                    token_type_ids
                ),
            )

        ort_inputs = {
            "input_ids":
                encoded["input_ids"]
                .numpy()
                .astype(np.int64),

            "attention_mask":
                encoded[
                    "attention_mask"
                ]
                .numpy()
                .astype(np.int64),

            "token_type_ids":
                token_type_ids
                .numpy()
                .astype(np.int64),
        }

        ort_intent, ort_slots = (
            session.run(
                None,
                ort_inputs,
            )
        )

        pt_intent_np = (
            pt_intent.numpy()
        )

        pt_slots_np = (
            pt_slots.numpy()
        )

        intent_error = np.max(
            np.abs(
                pt_intent_np
                - ort_intent
            )
        )

        slot_error = np.max(
            np.abs(
                pt_slots_np
                - ort_slots
            )
        )

        maximum_intent_error = max(
            maximum_intent_error,
            float(intent_error),
        )

        maximum_slot_error = max(
            maximum_slot_error,
            float(slot_error),
        )

        pt_intent_id = int(
            pt_intent_np.argmax(
                axis=-1
            )[0]
        )

        ort_intent_id = int(
            ort_intent.argmax(
                axis=-1
            )[0]
        )

        if (
            pt_intent_id
            == ort_intent_id
        ):
            intent_matches += 1

        mask = (
            encoded["attention_mask"][0]
            .numpy()
            .astype(bool)
        )

        pt_slot_ids = (
            pt_slots_np
            .argmax(axis=-1)[0]
        )

        ort_slot_ids = (
            ort_slots
            .argmax(axis=-1)[0]
        )

        slot_argmax_matches += int(
            np.sum(
                pt_slot_ids[mask]
                == ort_slot_ids[mask]
            )
        )

        slot_argmax_total += int(
            np.sum(mask)
        )

        print()
        print("TEXT:", text)

        print(
            "  intent match:",
            pt_intent_id
            == ort_intent_id,
        )

        print(
            "  intent max diff:",
            f"{intent_error:.8f}",
        )

        print(
            "  slot max diff:",
            f"{slot_error:.8f}",
        )

    print()
    print("=" * 70)
    print("ONNX PARITY SUMMARY")
    print("=" * 70)

    print(
        "Intent argmax:",
        f"{intent_matches}/"
        f"{len(TEST_COMMANDS)}",
    )

    print(
        "Slot argmax:",
        f"{slot_argmax_matches}/"
        f"{slot_argmax_total}",
    )

    print(
        "Max intent difference:",
        f"{maximum_intent_error:.8f}",
    )

    print(
        "Max slot difference:",
        f"{maximum_slot_error:.8f}",
    )

    if maximum_intent_error > 1e-3:
        raise RuntimeError(
            "Intent ONNX parity failed"
        )

    if maximum_slot_error > 1e-3:
        raise RuntimeError(
            "Slot ONNX parity failed"
        )

    print()
    print("ONNX PARITY PASSED")


if __name__ == "__main__":
    main()
