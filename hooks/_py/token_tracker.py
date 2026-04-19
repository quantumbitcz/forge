"""Token accumulator + cost estimator (replaces forge-token-tracker.sh)."""
from __future__ import annotations

import json
from pathlib import Path

from .state_write import update_state

# $ per million tokens. Pricing tracks the models actually used by the plugin.
MODEL_COST = {
    "sonnet":   {"prompt": 3.00, "completion": 15.00},
    "opus":     {"prompt": 15.00, "completion": 75.00},
    "haiku":    {"prompt": 0.80, "completion": 4.00},
}


def estimate_cost_usd(*, prompt: int, completion: int, model: str) -> float:
    rates = MODEL_COST.get(model.lower())
    if rates is None:
        return 0.0
    return (
        (prompt * rates["prompt"]) + (completion * rates["completion"])
    ) / 1_000_000.0


def record_usage(
    state_path: Path,
    *,
    agent: str,
    prompt: int,
    completion: int,
    model: str,
) -> None:
    cost = estimate_cost_usd(prompt=prompt, completion=completion, model=model)
    patch = {
        "tokens": {
            "total": {"prompt": prompt, "completion": completion, "cost_usd": cost},
            "by_agent": {agent: {"prompt": prompt, "completion": completion, "cost_usd": cost}},
        }
    }
    # Need an accumulating merge — read-modify-write under lock.
    from .io_utils import atomic_json_update

    def _mutate(current: dict) -> dict:
        tokens = current.setdefault("tokens", {})
        total = tokens.setdefault("total", {"prompt": 0, "completion": 0, "cost_usd": 0.0})
        total["prompt"] = int(total.get("prompt", 0)) + prompt
        total["completion"] = int(total.get("completion", 0)) + completion
        total["cost_usd"] = float(total.get("cost_usd", 0.0)) + cost
        by_agent = tokens.setdefault("by_agent", {})
        row = by_agent.setdefault(
            agent, {"prompt": 0, "completion": 0, "cost_usd": 0.0}
        )
        row["prompt"] = int(row.get("prompt", 0)) + prompt
        row["completion"] = int(row.get("completion", 0)) + completion
        row["cost_usd"] = float(row.get("cost_usd", 0.0)) + cost
        current["_seq"] = int(current.get("_seq", 0)) + 1
        return current

    atomic_json_update(state_path, _mutate, default={})


def ceiling_exceeded(state_path: Path, *, max_usd: float) -> bool:
    try:
        doc = json.loads(state_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return False
    total = ((doc.get("tokens") or {}).get("total") or {}).get("cost_usd", 0.0)
    return float(total) > max_usd
