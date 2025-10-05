# IPV Detection Experiment Harness

This repository packages our LLM-based IPV detection workflows: reproducible prompt experiments, a structured
SQLite/PostgreSQL store, and reporting utilities for NVDRS suicide narratives.

## Feature Highlights

- **Config-driven runs.** YAML files under `configs/experiments/` define model, prompt, dataset, and runtime
  options. No code edits needed to try new prompts.
- **Structured logging.** Each run writes narrative-level results, token usage, and confusion-matrix flags to
  `data/experiments.db`. Logs live in `logs/experiments/<experiment_id>/`.
- **One-command orchestration.** `scripts/run_experiment.R` handles data loading, experiment registration,
  LLM calls, exports, and summary stats (F1, precision, recall, accuracy).
- **PostgreSQL mirror.** `scripts/sync_sqlite_to_postgres.sh` copies the SQLite results into a remote Postgres
  instance for shared dashboards or ad-hoc SQL analysis.
- **Prompt comparison reports.** Completed-run metrics (ranked by F1) are published in
  `docs/20251004-experiment_results_report.md`.

## Repository Layout

```
R/                      # Production R functions (LLM calls, parsing, metrics, DB access)
R/legacy/               # Archived pre-refactor helpers (kept for reference)
configs/experiments/    # YAML experiment definitions (prompt + model sweeps)
configs/prompts/        # External prompt text snippets (optional)
data/experiments.db     # Primary SQLite store (git-ignored)
benchmark_results/      # CSV/JSON exports produced by past experiments
logs/experiments/       # Run-specific log directories (git-ignored, structure kept for reference)
docs/                   # Plans, status reports, analysis notebooks, generated summaries
scripts/                # CLI utilities (run_experiment.R, sync_sqlite_to_postgres.sh, canned batches)
tests/                  # Manual and automated test harnesses
```

Only the active production code paths live under `R/`, `scripts/`, `configs/`, and `tests/testthat`. Everything else
is documentation or archived artifacts for traceability.

## Quick Start

1. **Install prerequisites.** R 4.3+, `Rscript`, and an OpenAI-compatible endpoint (e.g. LM Studio). In R:
   ```r
   install.packages(c(
     "DBI", "RSQLite", "yaml", "httr2", "jsonlite", "readxl", "dplyr",
     "tibble", "tidyr", "uuid", "here"
   ))
   ```
2. **Configure the LLM endpoint.** Create `.Renviron` entries or export environment variables:
   ```bash
   export LLM_API_URL="http://localhost:1234/v1/chat/completions"
   export LLM_MODEL="mlx-community/gpt-oss-120b"
   ```
3. **Copy a base experiment.**
   ```bash
   cp configs/experiments/exp_037_baseline_v4_t00_medium.yaml configs/experiments/my_run.yaml
   # adjust prompt/version/temperature as desired
   ```
4. **Run it.**
   ```bash
   Rscript scripts/run_experiment.R configs/experiments/my_run.yaml
   ```
   Results go to `data/experiments.db`; CSV/JSON exports land in `benchmark_results/`; logs appear in
   `logs/experiments/<experiment_id>/`.
5. **Inspect results.**
   ```r
   library(DBI)
   conn <- dbConnect(RSQLite::SQLite(), "data/experiments.db")
   dbGetQuery(conn, "SELECT experiment_name, f1_ipv, precision_ipv, recall_ipv FROM experiments ORDER BY created_at DESC LIMIT 5")
   dbDisconnect(conn)
   ```

## Syncing to PostgreSQL

1. Ensure `.env` contains the desired connection, for example:
   ```bash
   PG_HOST=memini.lan
   PG_PORT=5433
   PG_USER=postgres
   PG_PASSWORD=********
   PG_DATABASE=postgres
   PG_CONN_STR=postgresql://postgres:********@memini.lan:5433/postgres
   ```
2. Run the sync script:
   ```bash
   PG_CONN_STR=postgresql://postgres:********@memini.lan:5433/postgres \
   scripts/sync_sqlite_to_postgres.sh
   ```
   The script now reports SQLite counts, Postgres before/after totals, size delta, and elapsed time.

## Reporting & Documentation

- Latest performance summary: `docs/20251004-experiment_results_report.md`
- Experiment automation plan + schema: `docs/20251003-unified_experiment_automation_plan.md`
- Archived analyses: `docs/analysis/`
- Contributor guidelines for agents: `AGENTS.md`

## Testing

- Unit/integration tests:
  ```bash
  Rscript tests/testthat.R
  ```
- Manual smoke test of the infrastructure:
  ```bash
  Rscript tests/manual_test_experiment_setup.R
  ```
- Shell wrappers (optional): `tests/test_phase1.sh`, `tests/validate_phase1.sh`

## Ready for Merge?

- ✅ Only production paths remain in `R/`, `configs/`, `scripts/`, and `tests/`; legacy utilities live under
  `R/legacy/` for reference.
- ✅ Generated artefacts (`benchmark_results/`, `logs/`, analysis notebooks) are treated as documentation; no orphaned
  code paths remain.
- ✅ README, docs, and the Postgres sync script reflect the current workflow.
- ✅ Experiment metrics are exported and summarized in docs.

With the run pipeline, documentation, and retirement of unused helpers in place, this branch is ready to merge back
into the mainline.
