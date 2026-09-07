import json
from pathlib import Path

import torch
import torch.nn as nn
from transformers import AutoModel

from safetensors.torch import save_file, load_file


class JointCommandSLM(nn.Module):
    def __init__(
        self,
        backbone,
        num_intents,
        num_slots,
        dropout=0.1,
    ):
        super().__init__()

        self.backbone_name = backbone
        self.num_intents = num_intents
        self.num_slots = num_slots
        self.dropout_rate = dropout

        self.encoder = AutoModel.from_pretrained(backbone)

        hidden_size = self.encoder.config.hidden_size

        self.dropout = nn.Dropout(dropout)

        self.intent_classifier = nn.Linear(
            hidden_size,
            num_intents,
        )

        self.slot_classifier = nn.Linear(
            hidden_size,
            num_slots,
        )

    def forward(
        self,
        input_ids,
        attention_mask,
        token_type_ids=None,
    ):
        kwargs = {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
        }

        if token_type_ids is not None:
            kwargs["token_type_ids"] = token_type_ids

        outputs = self.encoder(**kwargs)

        sequence_output = outputs.last_hidden_state

        cls_output = sequence_output[:, 0, :]

        intent_logits = self.intent_classifier(
            self.dropout(cls_output)
        )

        slot_logits = self.slot_classifier(
            self.dropout(sequence_output)
        )

        return intent_logits, slot_logits

    def save_checkpoint(
        self,
        output_dir,
        max_length,
    ):
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        config = {
            "backbone": self.backbone_name,
            "num_intents": self.num_intents,
            "num_slots": self.num_slots,
            "dropout": self.dropout_rate,
            "max_length": max_length,
        }

        with open(output_dir / "model_config.json", "w") as f:
            json.dump(config, f, indent=2)

        state_dict = {
            k: v.detach().cpu().contiguous()
            for k, v in self.state_dict().items()
        }

        save_file(
            state_dict,
            str(output_dir / "model.safetensors")
        )

    @classmethod
    def load_checkpoint(cls, checkpoint_dir, device="cpu"):
        checkpoint_dir = Path(checkpoint_dir)

        with open(
            checkpoint_dir / "model_config.json",
            encoding="utf-8",
        ) as f:
            config = json.load(f)

        model = cls(
            backbone=config["backbone"],
            num_intents=config["num_intents"],
            num_slots=config["num_slots"],
            dropout=config.get("dropout", 0.1),
        )

        state_dict = load_file(
            str(checkpoint_dir / "model.safetensors")
        )

        model.load_state_dict(state_dict, strict=True)
        model.to(device)

        return model, config
