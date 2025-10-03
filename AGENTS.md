# Repository Guidelines

## Project Structure & Module Organization
Core package code lives in `R/`, grouped by responsibility: API calls (`call_llm*`), prompt helpers, persistence utilities, and experiment tooling. Unit tests mirror the layout under `tests/testthat`, while `tests/integration` and `tests/performance` hold scenario scripts that hit real services or large corpora. Schema files belong in `inst/sql`, with migration and benchmark runners in `scripts/`. Keep generated artifacts in `results/`, `benchmark_results/`, and `logs/` out of commits unless you are publishing reproducible evidence.

## Build, Test, and Development Commands
Kick off an interactive session by sourcing the defaults and loading code:
```sh
R -q -e "source('R/0_setup.R'); devtools::load_all()"
```
Run the standard unit suite using the harness provided by the repo:
```sh
Rscript tests/testthat.R
```
For profile or batch experiments, execute the scripted entry points (e.g. `Rscript scripts/run_benchmark.R`). When distributing package builds, rely on the base tooling: `R CMD build .` followed by `R CMD check IPVdetection_*.tar.gz`.

## Coding Style & Naming Conventions
Use two-space indentation and keep arguments vertically aligned when they span lines. Functions, files, and list columns follow `snake_case`; exported helpers carry descriptive prefixes (`call_`, `store_`, `parse_`). Document R functions with roxygen2 blocks and prefer explicit namespace qualifiers (`httr2::`, `jsonlite::`). When adding SQL, mirror the naming found in `inst/sql/schema.sql` and keep keywords uppercase.

## Testing Guidelines
New behavior needs a `test-*.R` file or case inside the existing testthat modules; snapshot expectations live in `tests/testthat/_snaps`. Favor deterministic fixtures and isolate network access by mocking `httr2::req_perform`. Run `Rscript tests/testthat.R` locally before pushing, and note that performance scripts rely on live LLM endpoints—gate them behind environment checks.

## Commit & Pull Request Guidelines
Commits follow concise, imperative summaries (`Benchmark improvements`, `Issue #7: Add …`). Reference issues with the `Issue #n:` prefix when applicable and keep scope tight. Pull requests should describe the change, list test commands executed, and call out any updates to schemas or external interfaces; include screenshots only when UI artifacts are touched.

## Security & Configuration Tips
Set LLM connection details through `.Renviron` (see `README_SETUP.md`) and never commit secrets. SQLite (`llm_results.db`, `experiments.db`) and Postgres credentials belong in local config files ignored by git. When sharing benchmark outputs, scrub narrative content or replace it with redacted examples.
