# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

## Common Commands

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
# Full test suite (207 tests)
Rscript -e "testthat::test_dir('tests/testthat')"

# Integration tests only
Rscript tests/integration/run_integration_tests.R

# Single test file
Rscript -e "testthat::test_file('tests/testthat/test-call_llm.R')"
```

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

## File Organization

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

## Development Rules

**Code Style:**
- Follow Tidyverse style guide
- One function per R file
- `trimws()` all text inputs (always has trailing spaces)
- Use `here::here()` for paths

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

## Testing Philosophy

- Use test-runner agent to execute tests
- No mock services ever - test against real implementations
- One test at a time - complete before moving to next
- If test fails, check test structure before refactoring code
- Tests must be verbose for debugging

## Git Workflow

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

## Tone

- Be concise, direct, skeptical
- Criticism is welcome - point out mistakes or better approaches
- Tell me if there's a relevant standard or convention I'm unaware of
- Ask questions when intent is unclear - don't guess
- No flattery, no compliments unless specifically requested
- Occasional pleasantries are fine

## Publication Readiness

See `docs/20251005-publication_readiness_plan.md` for detailed plan to prepare this repository for publication as supplementary materials to peer-reviewed paper.
