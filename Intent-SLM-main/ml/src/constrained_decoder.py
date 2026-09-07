import torch


NEG_INF = -1e9


def split_label(label):
    if label == "O":
        return "O", None

    if "-" not in label:
        return label, None

    return label.split("-", 1)


def legal_start(label):
    """
    A sequence may start with:
        O
        B-X

    It should not start with:
        I-X
    """

    prefix, _ = split_label(label)

    return (
        prefix == "O"
        or prefix == "B"
    )


def legal_transition(
    previous_label,
    current_label,
):
    """
    BIO rules.

    O can follow anything.
    B-X can follow anything.

    I-X can only follow:
        B-X
        I-X
    """

    current_prefix, current_type = (
        split_label(current_label)
    )

    if current_prefix == "O":
        return True

    if current_prefix == "B":
        return True

    if current_prefix != "I":
        return False

    previous_prefix, previous_type = (
        split_label(previous_label)
    )

    if previous_prefix not in ("B", "I"):
        return False

    return (
        previous_type == current_type
    )


def apply_intent_mask(
    logits,
    allowed_ids,
):
    """
    logits:
        [num_words, num_slot_labels]
    """

    masked = torch.full_like(
        logits,
        NEG_INF,
    )

    masked[:, allowed_ids] = (
        logits[:, allowed_ids]
    )

    return masked


def constrained_viterbi(
    logits,
    id2slot,
    allowed_ids=None,
):
    """
    BIO-constrained Viterbi decoding.

    logits:
        [T, S]

    Returns:
        list[int]
    """

    if logits.size(0) == 0:
        return []

    logits = logits.detach().cpu()

    if allowed_ids is not None:
        logits = apply_intent_mask(
            logits,
            allowed_ids,
        )

    num_steps = logits.size(0)
    num_labels = logits.size(1)

    labels = [
        id2slot[str(i)]
        for i in range(num_labels)
    ]

    transition = torch.full(
        (num_labels, num_labels),
        NEG_INF,
        dtype=logits.dtype,
    )

    for previous in range(num_labels):

        for current in range(num_labels):

            if legal_transition(
                labels[previous],
                labels[current],
            ):
                transition[
                    previous,
                    current,
                ] = 0.0

    scores = torch.full(
        (num_steps, num_labels),
        NEG_INF,
        dtype=logits.dtype,
    )

    backpointers = torch.zeros(
        (num_steps, num_labels),
        dtype=torch.long,
    )

    #
    # Initial state.
    #
    for label_id in range(num_labels):

        if legal_start(
            labels[label_id]
        ):
            scores[0, label_id] = (
                logits[0, label_id]
            )

    #
    # Dynamic programming.
    #
    for t in range(1, num_steps):

        previous_scores = (
            scores[t - 1].unsqueeze(1)
            + transition
        )

        best_previous_score, best_previous = (
            previous_scores.max(dim=0)
        )

        scores[t] = (
            best_previous_score
            + logits[t]
        )

        backpointers[t] = best_previous

    #
    # Backtrack.
    #
    last = int(
        scores[-1].argmax().item()
    )

    sequence = [last]

    for t in range(
        num_steps - 1,
        0,
        -1,
    ):
        last = int(
            backpointers[
                t,
                last,
            ].item()
        )

        sequence.append(last)

    sequence.reverse()

    return sequence
