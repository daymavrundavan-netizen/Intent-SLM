import json
from pathlib import Path

import torch
import torch.nn as nn
from transformers import AutoModel
from safetensors.torch import save_file, load_file


class IntentConditionedCommandSLM(nn.Module):
    """
    V3 architecture.

    MiniLM encoder
        |
        +--> intent classifier
        |
        +--> token representations
                  |
          global CLS context
                  +
          predicted intent context
                  |
                  v
            slot classifier

    New context layers are zero-initialized so that when we
    initialize from the V2/L12 checkpoint, V3 initially behaves
    almost exactly like the baseline model.
    """

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

        self.encoder = AutoModel.from_pretrained(
            backbone
        )

        hidden_size = (
            self.encoder.config.hidden_size
        )

        self.dropout = nn.Dropout(dropout)

        self.intent_classifier = nn.Linear(
            hidden_size,
            num_intents,
        )

        #
        # Learned representation for each intent.
        #
        self.intent_embedding = nn.Embedding(
            num_intents,
            hidden_size,
        )

        #
        # Explicit sentence-level context from CLS.
        #
        self.global_context_proj = nn.Linear(
            hidden_size,
            hidden_size,
        )

        #
        # Keep the same shape/name as the V2 slot
        # classifier so we can copy its trained weights.
        #
        self.slot_classifier = nn.Linear(
            hidden_size,
            num_slots,
        )

        #
        # Zero initialization means:
        #
        # conditioned_tokens ~= original_tokens
        #
        # at the beginning of V3 fine-tuning.
        #
        nn.init.zeros_(
            self.intent_embedding.weight
        )

        nn.init.zeros_(
            self.global_context_proj.weight
        )

        nn.init.zeros_(
            self.global_context_proj.bias
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
            kwargs[
                "token_type_ids"
            ] = token_type_ids

        outputs = self.encoder(**kwargs)

        sequence_output = (
            outputs.last_hidden_state
        )

        cls_output = (
            sequence_output[:, 0, :]
        )

        #
        # Intent prediction.
        #
        intent_logits = (
            self.intent_classifier(
                self.dropout(cls_output)
            )
        )

        #
        # Differentiable predicted-intent context.
        #
        # We intentionally use predicted probabilities
        # instead of gold intent labels so training and
        # inference use the same architecture.
        #
        intent_probs = torch.softmax(
            intent_logits,
            dim=-1,
        )

        intent_context = (
            intent_probs
            @ self.intent_embedding.weight
        )

        global_context = (
            self.global_context_proj(
                cls_output
            )
        )

        #
        # Inject sentence + intent information into
        # every token.
        #
        conditioned_output = (
            sequence_output
            + global_context.unsqueeze(1)
            + intent_context.unsqueeze(1)
        )

        slot_logits = self.slot_classifier(
            self.dropout(
                conditioned_output
            )
        )

        return intent_logits, slot_logits

    def initialize_from_baseline(
        self,
        baseline_checkpoint,
    ):
        """
        Load:
            encoder
            intent head
            slot head

        from the trained L12 baseline.

        V3-specific context parameters remain
        zero initialized.
        """

        baseline_checkpoint = Path(
            baseline_checkpoint
        )

        state = load_file(
            str(
                baseline_checkpoint
                / "model.safetensors"
            )
        )

        compatible = {}

        own_state = self.state_dict()

        for key, value in state.items():

            if key not in own_state:
                continue

            if (
                own_state[key].shape
                != value.shape
            ):
                continue

            compatible[key] = value

        result = self.load_state_dict(
            compatible,
            strict=False,
        )

        print(
            "Loaded baseline tensors:",
            len(compatible),
        )

        print(
            "New V3 tensors:",
            result.missing_keys,
        )

    def save_checkpoint(
        self,
        output_dir,
        max_length,
    ):
        output_dir = Path(output_dir)

        output_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

        config = {
            "architecture":
                "intent_conditioned_v3",

            "backbone":
                self.backbone_name,

            "num_intents":
                self.num_intents,

            "num_slots":
                self.num_slots,

            "dropout":
                self.dropout_rate,

            "max_length":
                max_length,
        }

        with open(
            output_dir / "model_config.json",
            "w",
        ) as f:
            json.dump(
                config,
                f,
                indent=2,
            )

        state = {
            key:
                value.detach()
                .cpu()
                .contiguous()

            for key, value
            in self.state_dict().items()
        }

        save_file(
            state,
            str(
                output_dir
                / "model.safetensors"
            ),
        )

    @classmethod
    def load_checkpoint(
        cls,
        checkpoint_dir,
        device="cpu",
    ):
        checkpoint_dir = Path(
            checkpoint_dir
        )

        with open(
            checkpoint_dir
            / "model_config.json",
            encoding="utf-8",
        ) as f:
            config = json.load(f)

        model = cls(
            backbone=config["backbone"],
            num_intents=config[
                "num_intents"
            ],
            num_slots=config[
                "num_slots"
            ],
            dropout=config.get(
                "dropout",
                0.1,
            ),
        )

        state = load_file(
            str(
                checkpoint_dir
                / "model.safetensors"
            )
        )

        model.load_state_dict(
            state,
            strict=True,
        )

        model.to(device)

        return model, config
