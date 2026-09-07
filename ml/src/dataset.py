import json

import torch
from torch.utils.data import Dataset


class SnipsDataset(Dataset):
    """
    SNIPS word-level dataset with WordPiece alignment.

    Important:
    SNIPS annotations are WORD-level BIO labels.

    A word such as:
        "temperature"
    might become multiple WordPieces.

    We supervise ONLY the first WordPiece and assign -100 to
    continuation pieces. CrossEntropyLoss(ignore_index=-100)
    therefore ignores those continuation pieces.

    This:
      1. preserves the official 72-label SNIPS inventory,
      2. avoids inventing labels such as I-condition_temperature,
      3. keeps Slot F1 comparable at the original word level.
    """

    def __init__(
        self,
        jsonl_path,
        tokenizer,
        intent2id,
        slot2id,
        max_length=48,
    ):
        self.examples = []

        with open(jsonl_path, encoding="utf-8") as f:
            for line in f:
                self.examples.append(json.loads(line))

        self.tokenizer = tokenizer
        self.intent2id = intent2id
        self.slot2id = slot2id
        self.max_length = max_length

    def __len__(self):
        return len(self.examples)

    def __getitem__(self, index):
        example = self.examples[index]

        words = example["tokens"]
        word_slot_labels = example["slots"]

        encoding = self.tokenizer(
            words,
            is_split_into_words=True,
            truncation=True,
            padding="max_length",
            max_length=self.max_length,
            return_tensors="pt",
        )

        word_ids = encoding.word_ids(batch_index=0)

        aligned_slots = []

        previous_word_id = None

        for word_id in word_ids:

            # [CLS], [SEP], [PAD], etc.
            if word_id is None:
                aligned_slots.append(-100)

            # Continuation WordPiece:
            # do NOT invent a new BIO label.
            elif word_id == previous_word_id:
                aligned_slots.append(-100)

            # First WordPiece for this original word.
            else:
                label = word_slot_labels[word_id]

                if label not in self.slot2id:
                    raise KeyError(
                        f"Unknown slot label {label!r} "
                        f"in example {index}"
                    )

                aligned_slots.append(
                    self.slot2id[label]
                )

            previous_word_id = word_id

        item = {
            "input_ids":
                encoding["input_ids"].squeeze(0),

            "attention_mask":
                encoding["attention_mask"].squeeze(0),

            "intent_labels":
                torch.tensor(
                    self.intent2id[example["intent"]],
                    dtype=torch.long,
                ),

            "slot_labels":
                torch.tensor(
                    aligned_slots,
                    dtype=torch.long,
                ),
        }

        if "token_type_ids" in encoding:
            item["token_type_ids"] = (
                encoding["token_type_ids"].squeeze(0)
            )

        return item
