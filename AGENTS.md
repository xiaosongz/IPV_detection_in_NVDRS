# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, etc.) when working with code in this repository.

## What This Project Does

LLM-based IPV detection in NVDRS suicide narratives. Core function:

```r
detect_ipv("text") → {detected: TRUE/FALSE, confidence: 0-1}
```

Config-driven experiment harness with SQLite/PostgreSQL storage, reproducible runs, and automated metrics reporting.

## Project Type

**Research Compendium** - Not a loadable R package. Scripts use `source()` to load functions from `R/`. Focus is reproducibility for publication, not distribution. Will be published as supplementary materials to paper.

**Current Stage:** Testing phase with 404 narratives across different prompts/models. Planning production run with 60k narratives once optimal configuration identified.

**Publication Goal:** Peer-reviewed paper with this repository as supplementary materials. Repository structure designed for reviewers to reproduce all findings.

## Architecture

**Two Layers:**
1. **Modular functions** (`R/`) - LLM calls, parsing, metrics, DB access, experiment logging (one function per file)
2. **Experiment orchestration** (`scripts/run_experiment.R`) - YAML-driven workflow with full tracking

**Database Schema:**
- `experiments` table: config, metrics (F1, precision, recall), timestamps
- `narratives` table: per-record results, predictions, token usage
- SQLite primary (`data/experiments.db`), Postgres mirror for dashboards

**Key Design Principle:** Unix philosophy - do one thing well. Scripts control loops, parallelization, error handling. R functions are minimal building blocks.

## Project Structure & Module Organization

Core package code lives in `R/`, grouped by responsibility: API calls (`call_llm*`), prompt helpers, persistence utilities, and experiment tooling. Unit tests mirror the layout under `tests/testthat`, while `tests/integration` and `tests/performance` hold scenario scripts that hit real services or large corpora. Schema files belong in `inst/sql`, with migration and benchmark runners in `scripts/`. Keep generated artifacts in `results/`, `benchmark_results/`, and `logs/` out of commits unless you are publishing reproducible evidence.

**File Organization:**
- `R/` - Modular functions (one function per file, sourced by scripts)
- `R/legacy/` - Archived code (reference only, don't modify)
- `configs/experiments/` - YAML experiment definitions
- `configs/prompts/` - External prompt templates
- `scripts/` - Entry points (run_experiment.R, sync scripts, analysis)
- `tests/testthat/` - Unit tests (207 tests)
- `tests/integration/` - Integration tests
- `data/experiments.db` - SQLite database (git-ignored)
- `docs/` - Documentation files (use `YYYYMMDD-` prefix for all new docs)
- `docs/analysis/` - Analysis notebooks and reports
- `benchmark_results/` - CSV/JSON exports (git-ignored)
- `logs/experiments/` - Per-run logs (git-ignored)

**File Naming Convention:**
- Documentation files: `YYYYMMDD-description.md` (e.g., `20251005-publication_readiness_plan.md`)
- Analysis reports: `YYYYMMDD-report_name.Rmd/html`
- Experiment configs: `exp_NNN_description.yaml`

## Common Commands

### Interactive Session / Build

Kick off an interactive session by sourcing the defaults and loading code:
```sh
R -q -e "source('R/0_setup.R'); devtools::load_all()"
```
When distributing package builds, rely on the base tooling: `R CMD build .` followed by `R CMD check IPVdetection_*.tar.gz`.

### Running Experiments
```bash
# Single experiment
Rscript scripts/run_experiment.R configs/experiments/exp_037_baseline_v4_t00_medium.yaml

# View experiment results
Rscript scripts/view_experiment.R <experiment_id>

# Batch experiments
bash scripts/run_experiments_037_051.sh
```

### Testing
```bash
# Standard unit suite via the repo-provided harness
Rscript tests/testthat.R

# Full test suite (207 tests), invoked directly
Rscript -e "testthat::test_dir('tests/testthat')"

# Integration tests only
Rscript tests/integration/run_integration_tests.R

# Single test file
Rscript -e "testthat::test_file('tests/testthat/test-call_llm.R')"
```
For profile or batch experiments, execute the scripted entry points (e.g. `Rscript scripts/run_benchmark.R`).

### Database Operations
```bash
# Sync SQLite → PostgreSQL
PG_CONN_STR=postgresql://user:pass@host:5433/db scripts/sync_sqlite_to_postgres.sh

# Query experiments
Rscript -e "
  library(DBI)
  conn <- dbConnect(RSQLite::SQLite(), 'data/experiments.db')
  dbGetQuery(conn, 'SELECT experiment_name, f1_ipv FROM experiments ORDER BY created_at DESC LIMIT 5')
  dbDisconnect(conn)
"
```

### Documentation
```bash
# Generate roxygen documentation (optional - for completeness)
Rscript -e "devtools::document()"

# Note: Functions are accessed via source(), not library()
# Roxygen docs kept for reference and potential future package conversion
```

## Coding Style & Naming Conventions

Use two-space indentation and keep arguments vertically aligned when they span lines. Functions, files, and list columns follow `snake_case`; exported helpers carry descriptive prefixes (`call_`, `store_`, `parse_`). Document R functions with roxygen2 blocks and prefer explicit namespace qualifiers (`httr2::`, `jsonlite::`). When adding SQL, mirror the naming found in `inst/sql/schema.sql` and keep keywords uppercase.

Additional style rules:
- Follow Tidyverse style guide
- One function per R file
- `trimws()` all text inputs (always has trailing spaces)
- Use `here::here()` for paths

## Testing Guidelines

New behavior needs a `test-*.R` file or case inside the existing testthat modules; snapshot expectations live in `tests/testthat/_snaps`. Favor deterministic fixtures. Run `Rscript tests/testthat.R` locally before pushing, and note that performance scripts rely on live LLM endpoints—gate them behind environment checks.

- Use test-runner agent to execute tests
- Unit/integration tests isolate the LLM/network layer via `testthat::local_mocked_bindings` (e.g. mocking `call_llm` — see `tests/testthat/test-integration.R`); benchmark and validation runs exercise real API implementations
- One test at a time - complete before moving to next
- If test fails, check test structure before refactoring code
- Tests must be verbose for debugging
- IMPLEMENT TEST FOR EVERY FUNCTION
- NO CHEATER TESTS - tests must reveal flaws, be verbose for debugging

> **Resolved 2026-07-06:** the two source files contradicted each other on mocking (AGENTS.md: mock `httr2::req_perform`; CLAUDE.md: "no mock services ever"). The test suite itself settles it — `local_mocked_bindings` is used throughout `tests/testthat/`. Rule above now reflects actual practice: mock the LLM/network boundary in unit/integration tests, use real APIs for benchmark/validation runs.

## Development Rules

**Absolute Rules:**
- NO PARTIAL IMPLEMENTATION - finish what you start
- NO CODE DUPLICATION - check existing codebase, reuse functions
- NO DEAD CODE - delete unused code completely
- NO INCONSISTENT NAMING - read existing codebase naming patterns
- IMPLEMENT TEST FOR EVERY FUNCTION
- NO CHEATER TESTS - tests must reveal flaws, be verbose for debugging
- NO OVER-ENGINEERING - simple functions over abstractions
- NO MIXED CONCERNS - separation of validation, DB, API layers
- NO RESOURCE LEAKS - close DB connections, clean up handles

**The Linus Test** (before any change):
1. Does this eliminate a special case? (Good)
2. Does this add a special case? (Reject)
3. Can this be done in user space? (Then don't add it)
4. Will this break existing usage? (Never)

## Agent Usage (Context Optimization)

**Think carefully and implement the most concise solution that changes as little code as possible.**

**Always use specialized agents:**

1. **file-analyzer** - For reading log files and verbose outputs. Provides concise, actionable summaries while dramatically reducing context usage.

2. **code-analyzer** - For code search, bug research, and logic tracing. Expert in code analysis and vulnerability detection.

3. **test-runner** - For running tests and analyzing results. Ensures full test output is captured for debugging while keeping main conversation clean. No approval dialogs interrupt the workflow.

Using agents keeps main conversation clean and optimizes context usage.

## Error Handling Philosophy

- **Fail fast** for critical config (missing text model)
- **Log and continue** for optional features (extraction model)
- **Graceful degradation** when external services unavailable
- **User-friendly messages** through resilience layer

## Commit & Pull Request Guidelines

Commits follow concise, imperative summaries (`Benchmark improvements`, `Issue #7: Add …`). Reference issues with the `Issue #n:` prefix when applicable and keep scope tight. Pull requests should describe the change, list test commands executed, and call out any updates to schemas or external interfaces; include screenshots only when UI artifacts are touched.

### Git Workflow

Branch naming: `issue-{number}` or `feature/{description}`

Commit format:
```bash
git checkout -b issue-4
git commit -m "Issue #4: Add database schema"
git commit -m "Issue #4: Add connection utilities"
git commit -m "Issue #4: Complete implementation - Closes #4"
git checkout master
git merge --no-ff issue-4
```

Main branch for PRs: `master`

## Security & Configuration Tips

Set LLM connection details through `.Renviron` (see `README_SETUP.md`) and never commit secrets. SQLite (`llm_results.db`, `experiments.db`) and Postgres credentials belong in local config files ignored by git. When sharing benchmark outputs, scrub narrative content or replace it with redacted examples.

## Tone

- Be concise, direct, skeptical
- Criticism is welcome - point out mistakes or better approaches
- Tell me if there's a relevant standard or convention I'm unaware of
- Ask questions when intent is unclear - don't guess
- No flattery, no compliments unless specifically requested
- Occasional pleasantries are fine

## Publication Readiness

See `docs/20251005-publication_readiness_plan.md` for detailed plan to prepare this repository for publication as supplementary materials to peer-reviewed paper.
