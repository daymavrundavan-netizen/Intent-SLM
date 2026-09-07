import argparse
from pathlib import Path

import onnx
import onnxruntime as ort
from onnxruntime.quantization import (
    QuantType,
    quantize_dynamic,
)


TASK_PATTERNS = [
    "intent_classifier",
    "slot_classifier",
    "global_context_proj",
    "intent_embedding",
]


def node_text(node):
    return " ".join(
        [node.name]
        + list(node.input)
        + list(node.output)
    ).lower()


def find_nodes(model, patterns):
    patterns = [
        p.lower()
        for p in patterns
    ]

    matches = []

    for node in model.graph.node:
        text = node_text(node)

        if any(
            pattern in text
            for pattern in patterns
        ):
            matches.append(node.name)

    return sorted(set(matches))


def layer_patterns(layer_number):
    return [
        f"layer.{layer_number}",
        f"layer/{layer_number}",
        f"layer_{layer_number}",
        f"layer{layer_number}",
    ]


def quantize_variant(
    input_path,
    output_path,
    per_channel,
    excluded_nodes,
):
    print()
    print("=" * 72)
    print("Creating:", output_path.name)
    print("=" * 72)

    print(
        "Per channel :",
        per_channel,
    )

    print(
        "Excluded nodes:",
        len(excluded_nodes),
    )

    quantize_dynamic(
        model_input=str(input_path),
        model_output=str(output_path),
        weight_type=QuantType.QInt8,
        per_channel=per_channel,
        nodes_to_exclude=excluded_nodes,
    )

    session = ort.InferenceSession(
        str(output_path),
        providers=[
            "CPUExecutionProvider"
        ],
    )

    size_mb = (
        output_path.stat().st_size
        / (1024 * 1024)
    )

    print(
        f"Size: {size_mb:.2f} MB"
    )

    print(
        "Inputs:",
        [
            item.name
            for item in session.get_inputs()
        ],
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--input",
        required=True,
    )

    parser.add_argument(
        "--output-dir",
        required=True,
    )

    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output_dir)

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    model = onnx.load(
        str(input_path)
    )

    task_nodes = find_nodes(
        model,
        TASK_PATTERNS,
    )

    last1_nodes = find_nodes(
        model,
        TASK_PATTERNS
        + layer_patterns(11),
    )

    last2_nodes = find_nodes(
        model,
        TASK_PATTERNS
        + layer_patterns(10)
        + layer_patterns(11),
    )

    print("=" * 72)
    print("QUANTIZATION SWEEP")
    print("=" * 72)

    print(
        "Task-sensitive nodes found:",
        len(task_nodes),
    )

    print(
        "Task + last layer nodes:",
        len(last1_nodes),
    )

    print(
        "Task + last 2 layers nodes:",
        len(last2_nodes),
    )

    if task_nodes:
        print()
        print("Example task nodes:")

        for name in task_nodes[:10]:
            print(" ", name)

    quantize_variant(
        input_path,
        output_dir
        / "command_slm_int8_per_tensor.onnx",
        per_channel=False,
        excluded_nodes=[],
    )

    quantize_variant(
        input_path,
        output_dir
        / "command_slm_int8_heads_fp32.onnx",
        per_channel=True,
        excluded_nodes=task_nodes,
    )

    quantize_variant(
        input_path,
        output_dir
        / "command_slm_int8_last1_fp32.onnx",
        per_channel=True,
        excluded_nodes=last1_nodes,
    )

    quantize_variant(
        input_path,
        output_dir
        / "command_slm_int8_last2_fp32.onnx",
        per_channel=True,
        excluded_nodes=last2_nodes,
    )

    print()
    print("=" * 72)
    print("SWEEP COMPLETE")
    print("=" * 72)


if __name__ == "__main__":
    main()
