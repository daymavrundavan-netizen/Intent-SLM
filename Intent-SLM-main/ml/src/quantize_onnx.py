import argparse
from pathlib import Path

import onnxruntime as ort
from onnxruntime.quantization import (
    QuantType,
    quantize_dynamic,
)


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--input",
        required=True,
    )

    parser.add_argument(
        "--output",
        required=True,
    )

    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    output_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    print("=" * 70)
    print("QUANTIZING COMMAND SLM")
    print("=" * 70)

    print("Input :", input_path)
    print("Output:", output_path)

    quantize_dynamic(
        model_input=str(input_path),
        model_output=str(output_path),
        weight_type=QuantType.QInt8,
        per_channel=True,
    )

    #
    # Verify ONNX Runtime can actually load it.
    #
    session = ort.InferenceSession(
        str(output_path),
        providers=[
            "CPUExecutionProvider"
        ],
    )

    print(
        "ORT inputs:",
        [
            x.name
            for x in session.get_inputs()
        ],
    )

    fp32_mb = (
        input_path.stat().st_size
        / (1024 * 1024)
    )

    int8_mb = (
        output_path.stat().st_size
        / (1024 * 1024)
    )

    print()
    print(
        f"FP32 size : {fp32_mb:.2f} MB"
    )

    print(
        f"INT8 size : {int8_mb:.2f} MB"
    )

    print(
        f"Reduction : "
        f"{100 * (1 - int8_mb / fp32_mb):.1f}%"
    )

    print()
    print("INT8 QUANTIZATION COMPLETE")


if __name__ == "__main__":
    main()
