import argparse
import json
import shutil
from pathlib import Path

import onnx
import torch
import torch.nn as nn
from transformers import AutoTokenizer

from model_v3 import IntentConditionedCommandSLM


class ExportWrapper(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(
        self,
        input_ids,
        attention_mask,
        token_type_ids,
    ):
        intent_logits, slot_logits = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            token_type_ids=token_type_ids,
        )

        return intent_logits, slot_logits


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--checkpoint",
        required=True,
    )

    parser.add_argument(
        "--output-dir",
        required=True,
    )

    args = parser.parse_args()

    checkpoint = Path(args.checkpoint)
    output_dir = Path(args.output_dir)

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

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

    max_length = config["max_length"]

    sample = tokenizer(
        "play a song by adele",
        truncation=True,
        padding="max_length",
        max_length=max_length,
        return_tensors="pt",
    )

    input_ids = sample["input_ids"]

    attention_mask = sample[
        "attention_mask"
    ]

    token_type_ids = sample.get(
        "token_type_ids"
    )

    if token_type_ids is None:
        token_type_ids = torch.zeros_like(
            input_ids
        )

    wrapper = ExportWrapper(model)

    wrapper.eval()

    output_file = (
        output_dir / "command_slm_fp32.onnx"
    )

    print("=" * 70)
    print("EXPORTING FROZEN COMMAND SLM")
    print("=" * 70)

    print("Checkpoint :", checkpoint)
    print("Output     :", output_file)
    print("Max length :", max_length)
    print()

    with torch.no_grad():
        torch.onnx.export(
            wrapper,
            (
                input_ids,
                attention_mask,
                token_type_ids,
            ),
            str(output_file),

            input_names=[
                "input_ids",
                "attention_mask",
                "token_type_ids",
            ],

            output_names=[
                "intent_logits",
                "slot_logits",
            ],

            opset_version=17,

            do_constant_folding=True,

            dynamo=False,
        )

    print("Checking ONNX model...")

    onnx_model = onnx.load(
        str(output_file)
    )

    onnx.checker.check_model(
        onnx_model
    )

    print("ONNX CHECK PASSED")

    #
    # Copy everything mobile inference needs.
    #
    support_files = [
        "model_config.json",
        "intent2id.json",
        "id2intent.json",
        "slot2id.json",
        "id2slot.json",
        "intent_slot_compat.json",
    ]

    for filename in support_files:
        source = checkpoint / filename

        if source.exists():
            shutil.copy2(
                source,
                output_dir / filename,
            )

    tokenizer_output = (
        output_dir / "tokenizer"
    )

    if tokenizer_output.exists():
        shutil.rmtree(
            tokenizer_output
        )

    shutil.copytree(
        checkpoint / "tokenizer",
        tokenizer_output,
    )

    metadata = {
        "model":
            "CDAC Command SLM V4",

        "architecture":
            "IntentConditionedCommandSLM",

        "onnx_file":
            "command_slm_fp32.onnx",

        "max_length":
            max_length,

        "inputs": [
            "input_ids",
            "attention_mask",
            "token_type_ids",
        ],

        "outputs": [
            "intent_logits",
            "slot_logits",
        ],

        "deployment_decoder": [
            "intent_slot_mask",
            "bio_constrained_viterbi",
        ],
    }

    with open(
        output_dir / "deployment.json",
        "w",
        encoding="utf-8",
    ) as f:
        json.dump(
            metadata,
            f,
            indent=2,
        )

    size_mb = (
        output_file.stat().st_size
        / (1024 * 1024)
    )

    print()
    print(
        f"ONNX size: {size_mb:.2f} MB"
    )

    print(
        "Export directory:",
        output_dir,
    )

    print()
    print(
        "FP32 ONNX EXPORT COMPLETE"
    )


if __name__ == "__main__":
    main()
