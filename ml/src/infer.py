import argparse
import json
import re
from pathlib import Path

import torch
from transformers import AutoTokenizer

from model import JointCommandSLM


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def split_words_with_spans(text):
    """
    Split text on whitespace while preserving exact character spans.

    Example:
        "weather in Mumbai"
    =>
        words = ["weather", "in", "Mumbai"]
        spans = [(0,7), (8,10), (11,17)]
    """
    matches = list(re.finditer(r"\S+", text))

    words = [
        match.group(0)
        for match in matches
    ]

    spans = [
        (match.start(), match.end())
        for match in matches
    ]

    return words, spans


def decode_word_slots(
    text,
    word_spans,
    labels,
):
    """
    Decode word-level BIO predictions into slot/value pairs.
    """

    entities = []

    current_type = None
    current_start = None
    current_end = None

    def close_current():
        nonlocal current_type
        nonlocal current_start
        nonlocal current_end

        if current_type is not None:
            value = text[
                current_start:current_end
            ].strip()

            if value:
                entities.append(
                    (current_type, value)
                )

        current_type = None
        current_start = None
        current_end = None

    for (start, end), label in zip(
        word_spans,
        labels,
    ):

        if label == "O":
            close_current()
            continue

        if "-" not in label:
            close_current()
            continue

        prefix, slot_type = label.split("-", 1)

        if prefix == "B":
            close_current()

            current_type = slot_type
            current_start = start
            current_end = end

        elif prefix == "I":

            # Normal continuation.
            if current_type == slot_type:
                current_end = end

            # Repair invalid I-X following something else.
            else:
                close_current()

                current_type = slot_type
                current_start = start
                current_end = end

        else:
            close_current()

    close_current()

    result = {}

    for slot_type, value in entities:

        if slot_type not in result:
            result[slot_type] = value

        else:
            # Rare repeated slot type.
            result[slot_type] = (
                result[slot_type] + " " + value
            )

    return result


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("checkpoint")
    parser.add_argument("text", nargs="+")

    args = parser.parse_args()

    text = " ".join(args.text)

    checkpoint = Path(args.checkpoint)

    device = torch.device(
        "cuda"
        if torch.cuda.is_available()
        else "cpu"
    )

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

    words, word_spans = split_words_with_spans(
        text
    )

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

    model_inputs = {
        key: value.to(device)
        for key, value in encoding.items()
    }

    with torch.no_grad():

        intent_logits, slot_logits = model(
            input_ids=model_inputs[
                "input_ids"
            ],
            attention_mask=model_inputs[
                "attention_mask"
            ],
            token_type_ids=model_inputs.get(
                "token_type_ids"
            ),
        )

    intent_probs = torch.softmax(
        intent_logits,
        dim=-1,
    )[0]

    intent_id = int(
        intent_probs.argmax().item()
    )

    intent = id2intent[str(intent_id)]

    token_slot_ids = (
        slot_logits.argmax(dim=-1)[0]
        .detach()
        .cpu()
        .tolist()
    )

    # Convert WordPiece predictions back to ONE prediction
    # per original word.
    word_predictions = {}

    for token_index, word_id in enumerate(
        word_ids
    ):
        if word_id is None:
            continue

        # Only first WordPiece prediction.
        if word_id in word_predictions:
            continue

        word_predictions[word_id] = (
            token_slot_ids[token_index]
        )

    predicted_labels = []

    usable_word_spans = []

    for word_id in range(len(words)):

        # Sentence may have been truncated.
        if word_id not in word_predictions:
            break

        predicted_labels.append(
            id2slot[
                str(word_predictions[word_id])
            ]
        )

        usable_word_spans.append(
            word_spans[word_id]
        )

    slots = decode_word_slots(
        text,
        usable_word_spans,
        predicted_labels,
    )

    result = {
        "intent": intent,
        "slots": slots,
    }

    print(
        json.dumps(
            result,
            indent=2,
            ensure_ascii=False,
        )
    )

    print(
        "\nIntent confidence:",
        round(
            float(
                intent_probs[intent_id]
            ),
            4,
        ),
    )


if __name__ == "__main__":
    main()
