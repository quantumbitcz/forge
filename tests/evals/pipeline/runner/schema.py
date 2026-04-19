"""Pydantic models for the pipeline eval harness.

Schema reference for scenario authors:
    id:                       str — scenario directory name, e.g. "01-ts-microservice-greenfield"
    mode:                     "standard" | "bugfix" | "migration" | "bootstrap"
    token_budget:             positive int — upper bound; over-budget degrades adherence linearly
    elapsed_budget_seconds:   positive int — wall-clock target in seconds
    min_pipeline_score:       int in [0, 100] — floor for pipeline_score component
    required_verdict:         "PASS" | "CONCERNS" — never FAIL in frozen scenarios
    touched_files_expected:   list[str] — overlap metric (reporting-only)
    must_not_touch:           list[str] — glob patterns; hard fail if pipeline edits any
    notes:                    str — free-form author notes
"""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


Mode = Literal["standard", "bugfix", "migration", "bootstrap"]
Verdict = Literal["PASS", "CONCERNS"]
ResultVerdict = Literal["PASS", "CONCERNS", "FAIL", "DRY_RUN"]
Status = Literal["completed", "timeout", "error", "dry_run"]


class Expected(BaseModel):
    """Parsed ``expected.yaml`` contents for a scenario."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    mode: Mode
    token_budget: int = Field(gt=0)
    elapsed_budget_seconds: int = Field(gt=0)
    min_pipeline_score: int = Field(ge=0, le=100)
    required_verdict: Verdict
    touched_files_expected: list[str]
    must_not_touch: list[str]
    notes: str


class Scenario(BaseModel):
    """A discovered scenario: prompt text + parsed expected metadata."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    path: str
    prompt: str
    expected: Expected


class Finding(BaseModel):
    """An EVAL-* finding emitted by the harness (not the pipeline)."""

    model_config = ConfigDict(extra="forbid")

    category: str
    severity: Literal["CRITICAL", "WARNING", "INFO"]
    message: str


class Result(BaseModel):
    """One record per scenario per run. Serialized to ``.forge/eval-results.jsonl``."""

    model_config = ConfigDict(extra="forbid")

    scenario_id: str
    started_at: str
    ended_at: str
    actual_tokens: int
    actual_elapsed_seconds: int
    pipeline_score: float
    verdict: ResultVerdict
    touched_files_actual: list[str]
    overlap_jaccard: float
    token_adherence: float
    elapsed_adherence: float
    composite: float
    findings: list[Finding]
    status: Status
