import argparse
import json
import math
import random
import shutil
from contextlib import nullcontext
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from torch.optim import AdamW
from torch.utils.data import DataLoader
from transformers import (
    AutoTokenizer,
    get_linear_schedule_with_warmup,
)
from seqeval.metrics import f1_score

from dataset import SnipsDataset
from model_v3 import (
    IntentConditionedCommandSLM
)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def seed_everything(seed):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)

    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


@torch.no_grad()
def evaluate(
    model,
    loader,
    device,
    id2slot,
):
    model.eval()

    total = 0
    intent_correct = 0
    frame_correct = 0

    gold_sequences = []
    pred_sequences = []

    for batch in loader:

        batch = {
            key: value.to(device)
            for key, value
            in batch.items()
        }

        intent_logits, slot_logits = model(
            input_ids=batch["input_ids"],
            attention_mask=batch[
                "attention_mask"
            ],
            token_type_ids=batch.get(
                "token_type_ids"
            ),
        )

        intent_pred = (
            intent_logits.argmax(-1)
        )

        slot_pred = (
            slot_logits.argmax(-1)
        )

        for i in range(
            intent_pred.size(0)
        ):
            total += 1

            intent_ok = (
                intent_pred[i].item()
                ==
                batch[
                    "intent_labels"
                ][i].item()
            )

            if intent_ok:
                intent_correct += 1

            pred_tags = []
            gold_tags = []

            slots_ok = True

            for j in range(
                slot_pred.size(1)
            ):
                gold_id = (
                    batch[
                        "slot_labels"
                    ][i, j].item()
                )

                if gold_id == -100:
                    continue

                pred_id = (
                    slot_pred[i, j].item()
                )

                gold_tags.append(
                    id2slot[
                        str(gold_id)
                    ]
                )

                pred_tags.append(
                    id2slot[
                        str(pred_id)
                    ]
                )

                if pred_id != gold_id:
                    slots_ok = False

            gold_sequences.append(
                gold_tags
            )

            pred_sequences.append(
                pred_tags
            )

            if intent_ok and slots_ok:
                frame_correct += 1

    return {
        "intent_accuracy":
            intent_correct / total,

        "slot_f1":
            f1_score(
                gold_sequences,
                pred_sequences,
                zero_division=0,
            ),

        "exact_frame_accuracy":
            frame_correct / total,
    }


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--baseline-checkpoint",
        required=True,
    )

    parser.add_argument(
        "--output-dir",
        required=True,
    )

    parser.add_argument(
        "--data-dir",
        default="/workspace/ml/data/processed",
    )

    parser.add_argument(
        "--max-length",
        type=int,
        default=48,
    )

    parser.add_argument(
        "--batch-size",
        type=int,
        default=4,
    )

    parser.add_argument(
        "--grad-accum",
        type=int,
        default=8,
    )

    parser.add_argument(
        "--epochs",
        type=int,
        default=5,
    )

    parser.add_argument(
        "--lr",
        type=float,
        default=1e-5,
    )

    parser.add_argument(
        "--slot-loss-weight",
        type=float,
        default=1.5,
    )

    parser.add_argument(
        "--weight-decay",
        type=float,
        default=0.01,
    )

    parser.add_argument(
        "--warmup-ratio",
        type=float,
        default=0.05,
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=42,
    )

    args = parser.parse_args()

    seed_everything(args.seed)

    baseline = Path(
        args.baseline_checkpoint
    )

    output_dir = Path(
        args.output_dir
    )

    data_dir = Path(
        args.data_dir
    )

    with open(
        baseline
        / "model_config.json",
        encoding="utf-8",
    ) as f:
        baseline_config = json.load(f)

    backbone = (
        baseline_config["backbone"]
    )

    intent2id = load_json(
        baseline / "intent2id.json"
    )

    slot2id = load_json(
        baseline / "slot2id.json"
    )

    id2slot = load_json(
        baseline / "id2slot.json"
    )

    tokenizer = (
        AutoTokenizer.from_pretrained(
            baseline / "tokenizer",
            use_fast=True,
        )
    )

    train_dataset = SnipsDataset(
        data_dir / "train.jsonl",
        tokenizer,
        intent2id,
        slot2id,
        args.max_length,
    )

    valid_dataset = SnipsDataset(
        data_dir / "valid.jsonl",
        tokenizer,
        intent2id,
        slot2id,
        args.max_length,
    )

    device = torch.device(
        "cuda"
        if torch.cuda.is_available()
        else "cpu"
    )

    train_loader = DataLoader(
        train_dataset,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=2,
        pin_memory=(
            device.type == "cuda"
        ),
    )

    valid_loader = DataLoader(
        valid_dataset,
        batch_size=8,
        shuffle=False,
        num_workers=2,
        pin_memory=(
            device.type == "cuda"
        ),
    )

    model = IntentConditionedCommandSLM(
        backbone=backbone,
        num_intents=len(intent2id),
        num_slots=len(slot2id),
    )

    model.initialize_from_baseline(
        baseline
    )

    model.to(device)

    total_params = sum(
        p.numel()
        for p in model.parameters()
    )

    print("=" * 70)
    print("CDAC COMMAND SLM V3")
    print("=" * 70)
    print("Backbone :", backbone)
    print("Device   :", device)
    print(
        "Parameters:",
        f"{total_params:,}"
    )
    print(
        "Starting from:",
        baseline
    )
    print(
        "Slot loss weight:",
        args.slot_loss_weight
    )
    print(
        "Effective batch:",
        args.batch_size
        * args.grad_accum
    )
    print("=" * 70)

    optimizer = AdamW(
        model.parameters(),
        lr=args.lr,
        weight_decay=args.weight_decay,
    )

    steps_per_epoch = math.ceil(
        len(train_loader)
        / args.grad_accum
    )

    total_steps = (
        steps_per_epoch
        * args.epochs
    )

    warmup_steps = int(
        total_steps
        * args.warmup_ratio
    )

    scheduler = (
        get_linear_schedule_with_warmup(
            optimizer,
            num_warmup_steps=(
                warmup_steps
            ),
            num_training_steps=(
                total_steps
            ),
        )
    )

    intent_loss_fn = (
        nn.CrossEntropyLoss()
    )

    slot_loss_fn = (
        nn.CrossEntropyLoss(
            ignore_index=-100
        )
    )

    use_amp = (
        device.type == "cuda"
    )

    scaler = torch.amp.GradScaler(
        "cuda",
        enabled=use_amp,
    )

    best_exact = -1.0
    history = []

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    for epoch in range(
        1,
        args.epochs + 1,
    ):
        model.train()

        running_loss = 0.0

        optimizer.zero_grad(
            set_to_none=True
        )

        for step, batch in enumerate(
            train_loader
        ):
            batch = {
                key:
                    value.to(
                        device,
                        non_blocking=True,
                    )

                for key, value
                in batch.items()
            }

            amp_context = (
                torch.autocast(
                    device_type="cuda",
                    dtype=torch.float16,
                )
                if use_amp
                else nullcontext()
            )

            with amp_context:

                intent_logits, slot_logits = (
                    model(
                        input_ids=batch[
                            "input_ids"
                        ],
                        attention_mask=batch[
                            "attention_mask"
                        ],
                        token_type_ids=batch.get(
                            "token_type_ids"
                        ),
                    )
                )

                intent_loss = (
                    intent_loss_fn(
                        intent_logits,
                        batch[
                            "intent_labels"
                        ],
                    )
                )

                slot_loss = (
                    slot_loss_fn(
                        slot_logits.reshape(
                            -1,
                            slot_logits.size(-1),
                        ),
                        batch[
                            "slot_labels"
                        ].reshape(-1),
                    )
                )

                loss = (
                    intent_loss
                    +
                    args.slot_loss_weight
                    * slot_loss
                )

                scaled_loss = (
                    loss
                    / args.grad_accum
                )

            scaler.scale(
                scaled_loss
            ).backward()

            running_loss += (
                loss.item()
            )

            should_step = (
                (step + 1)
                % args.grad_accum == 0

                or

                (step + 1)
                == len(train_loader)
            )

            if should_step:

                scaler.unscale_(
                    optimizer
                )

                torch.nn.utils.clip_grad_norm_(
                    model.parameters(),
                    1.0,
                )

                scaler.step(
                    optimizer
                )

                scaler.update()

                optimizer.zero_grad(
                    set_to_none=True
                )

                scheduler.step()

        metrics = evaluate(
            model,
            valid_loader,
            device,
            id2slot,
        )

        average_loss = (
            running_loss
            / len(train_loader)
        )

        record = {
            "epoch": epoch,
            "train_loss":
                average_loss,
            **metrics,
        }

        history.append(record)

        print()
        print(
            f"Epoch {epoch}/"
            f"{args.epochs}"
        )

        print(
            f"  loss        : "
            f"{average_loss:.4f}"
        )

        print(
            f"  intent acc  : "
            f"{metrics['intent_accuracy']:.4f}"
        )

        print(
            f"  slot F1     : "
            f"{metrics['slot_f1']:.4f}"
        )

        print(
            f"  exact frame : "
            f"{metrics['exact_frame_accuracy']:.4f}"
        )

        if (
            metrics[
                "exact_frame_accuracy"
            ]
            > best_exact
        ):
            best_exact = metrics[
                "exact_frame_accuracy"
            ]

            print(
                "  >>> NEW BEST V3 MODEL"
            )

            model.save_checkpoint(
                output_dir,
                args.max_length,
            )

            tokenizer.save_pretrained(
                output_dir / "tokenizer"
            )

            for filename in [
                "intent2id.json",
                "id2intent.json",
                "slot2id.json",
                "id2slot.json",
                "intent_slot_compat.json",
            ]:
                source = (
                    baseline / filename
                )

                if source.exists():
                    shutil.copy2(
                        source,
                        output_dir
                        / filename,
                    )

            with open(
                output_dir
                / "best_metrics.json",
                "w",
            ) as f:
                json.dump(
                    record,
                    f,
                    indent=2,
                )

        with open(
            output_dir
            / "history.json",
            "w",
        ) as f:
            json.dump(
                history,
                f,
                indent=2,
            )

    print()
    print("=" * 70)
    print("V3 TRAINING COMPLETE")
    print(
        "Best raw exact frame:",
        f"{best_exact:.4f}",
    )
    print("=" * 70)


if __name__ == "__main__":
    main()
