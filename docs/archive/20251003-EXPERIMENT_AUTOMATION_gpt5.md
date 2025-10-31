# Experiment Automation Plan

## Goals
- Parameterize prompts/models via config; no manual script edits.
- Log experiment/run metadata up front; capture narrative-level outputs.
- Produce experiment-level metrics and summaries automatically at end.
- Make runs reproducible (config, versions, seeds) and auditable.

## High-Level Architecture
- Config-driven runs: YAML/JSON config checked into `configs/` describing model, prompts, dataset, batching, and limits.
- Orchestrator script: `scripts/run_experiment.R` that reads config, registers an experiment, streams narratives through the LLM, and writes results.
- Database-backed tracking: SQLite by default (upgradeable to Postgres) with normalized tables for experiments, runs, prompts, models, narratives, and predictions.
- Post-run summarizer: `scripts/summarize_experiment.R` computes metrics and writes them back to DB.

## Suggested DB Schema (minimal)
- `experiments(id, name, config_path, prompt_id, model_id, platform, author, seed, start_time, end_time, total_ms, notes)`
- `prompts(id, title, system_prompt, user_template, version, created_at)`
- `models(id, provider, model_name, version, params_json, created_at)`
- `runs(id, experiment_id, status, total_narratives, completed_narratives, created_at, finished_at)`
- `narratives(id, source, external_id, text_hash, length, created_at)`
- `predictions(id, run_id, narrative_id, detected, confidence, reasoning, rationale, latency_ms, error, created_at)`
- `labels(id, narrative_id, gold_flag, source, created_at)`  # manual flags
- `metrics(id, experiment_id, metric_name, metric_value, created_at)`

Notes:
- Keep narrative text out of DB or store a hash + local path for privacy; use `labels` to compare against manual flags.
- Add indexes on `(experiment_id)`, `(run_id)`, `(narrative_id)`.

## Config Format (example)
```yaml
name: "andrea_2025-09-02_ipv_benchmark"
author: "andrea"
platform: "LM Studio"
model:
  provider: "openai-compatible"
  name: "openai/gpt-oss-120b"
  params:
    temperature: 0.0
prompt:
  title: "ipv_detector_v3"
  system: "You are an IPV detector. Respond as JSON."
  user_template: "Analyze: {{narrative}}"
data:
  source: "data-raw/suicide_IPV_manuallyflagged.xlsx"
  text_column: "narrative"
  id_column: "case_id"
run:
  batch_size: 50
  max_records: null
  seed: 123
  retry: {max_attempts: 2, backoff_ms: 500}
```

## Orchestrator Flow (scripts/run_experiment.R)
1. Parse config; compute `config_hash` for provenance.
2. Upsert `prompts` and `models`; insert `experiments` with `start_time`.
3. Create `runs` record; load dataset and register `narratives` by hash + external id.
4. For each batch, call `call_llm()` with built messages, time each call, and write `predictions` rows (including `reasoning/rationale` if available).
5. On completion, set `runs.finished_at`; trigger summarizer.
6. Summarizer computes: count processed, success/fail, positives/negatives; compare to `labels` for TP/FP/FN/TN and overlap %. Write to `metrics` and `experiments.end_time/total_ms`.

## Code Integration (R)
- Add helpers in `R/experiment_utils.R`:
  - `register_experiment(config) -> experiment_id`
  - `register_run(experiment_id) -> run_id`
  - `upsert_prompt(prompt) -> prompt_id`, `upsert_model(model) -> model_id`
  - `ensure_schema(conn)` (extend `inst/sql/schema.sql`)
  - `record_prediction(run_id, narrative, result, timings)`
  - `compute_metrics(experiment_id)`
- Extend `call_llm()` to accept `temperature` and pass through config.
- Add `build_prompt()` variant supporting `user_template` substitution.

## CLI and Commands
- Run: `Rscript scripts/run_experiment.R --config configs/andrea_ipv.yaml`
- Summarize only: `Rscript scripts/summarize_experiment.R --experiment <id>`
- Export: `Rscript scripts/export_results.R --experiment <id> --out results/exp_<id>.csv`

## Testing & Reproducibility
- Unit-test registration, schema, and metrics with in-memory SQLite; mock `httr2::req_perform` for deterministic responses.
- Gate live runs behind env var `RUN_LIVE=1`.
- Persist config files per experiment and log `sessionInfo()` to DB.

## Migration Plan
1. Add/extend schema in `inst/sql/schema.sql`; implement `ensure_schema()`.
2. Create `configs/` and a first config for the current benchmark.
3. Implement `scripts/run_experiment.R` and `scripts/summarize_experiment.R` using existing `R/` utilities.
4. Backfill a few past runs by re-executing with archived prompts/models to validate pipeline.
5. Add tests in `tests/testthat/test-experiments.R` for schema, registration, and metrics.

## Best-Practice Notes
- Treat prompts and model params as first-class, versioned artifacts.
- Separate experiment metadata from per-narrative predictions; avoid storing raw PHI.
- Prefer SQLite for local R&D and Postgres for shared, concurrent workloads.
- Automate summaries as part of the run to ensure every experiment is comparable.

