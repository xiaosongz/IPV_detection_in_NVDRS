# Test Suite Rebuild Plan — 2025-10-04

## Goals
- Replace legacy-focused tests with coverage for the current experiment pipeline.
- Keep the suite deterministic (no live LLM calls unless explicitly allowed).
- Make it easy to run locally (`Rscript tests/testthat.R`) and integrate with CI later.

## 1. Audit Current Code Surface
| Area | Notes |
| --- | --- |
| Core modules | `config_loader.R`, `data_loader.R`, `db_schema.R`, `experiment_logger.R`, `experiment_queries.R`, `run_benchmark_core.R`, `parse_llm_result.R`, `repair_json.R`, `metrics.R`, `utils.R`, `call_llm.R`, `build_prompt.R` |
| Scripts | `scripts/run_experiment.R`, `scripts/sync_sqlite_to_postgres.sh` |
| Legacy | Everything under `R/legacy/` — exclude from new suite (optional archival tests only) |

## 2. Testing Principles (testthat best practices)
- Structure tests by feature/function (one `test-*.R` per feature area).
- Use fixtures/temp dirs to isolate file-based tests (`withr::with_tempdir`).
- Avoid network calls; mock/stub where necessary.
- Keep tests deterministic; gate live tests behind env vars (e.g. `RUN_LIVE_TESTS`).
- Prefer in-memory SQLite for DB tests (`RSQLite::SQLite(":memory:")`).
- Use snapshots sparingly for stable outputs.

## 3. New Tests by Module
| Module | Tests to implement |
| --- | --- |
| `config_loader.R` | `load_experiment_config()` loads embedded prompts & env vars; `validate_config()` rejects bad configs; `substitute_template()` handles placeholders |
| `data_loader.R` | `load_source_data()` loads Excel, coerces incident IDs to character, respects `force_reload`; `get_source_narratives()` respects `max_narratives` |
| `db_schema.R` | `init_experiment_db()` creates tables/indexes idempotently; `ensure_token_columns()` upgrades existing DBs; `get_db_connection()` errors when missing |
| `experiment_logger.R` | `start_experiment()` saves metadata; `log_narrative_result()` writes result with tokens; `compute_enhanced_metrics()` matches expected counts; `mark_experiment_failed()` marks status; `init_experiment_logger()` creates log files |
| `run_benchmark_core.R` | Processes sample narratives, logs outputs, handles parse errors; update processed counts; relies on mocked `call_llm()` |
| `parse_llm_result.R` & `repair_json.R` | Parse valid responses; handle missing usage; `repair_json()` fixes known patterns (snapshot) |
| `experiment_queries.R` | `list_experiments()`, `get_experiment_results()`, `compare_experiments()`, `find_disagreements()`, `analyze_experiment_errors()` return expected data |
| `metrics.R` / `utils.R` | Add direct tests for metric calculations as needed |
| Runner script | Smoke test `scripts/run_experiment.R` with tiny config & mocked LLM (gated by env var) |
| Sync script | (optional) test via separate integration or script-level checks |

## 4. Test Harness Updates
- Replace explicit `source()` list with dynamic loader:
  ```r
  library(testthat)
  library(here)
  r_files <- list.files(here("R"), pattern = "\\.[Rr]$", full.names = TRUE, recursive = FALSE)
  for (path in r_files) source(path)
  test_dir(here("tests", "testthat"))
  ```
- Exclude `R/legacy/` from automatic sourcing.
- Update or archive old tests (`test-db_utils.R`, etc.).

## 5. Fixtures & Helpers
- Add fixtures under `tests/fixtures/`:
  - `configs/` (YAML examples)
  - `data/` (small Excel file)
  - `responses/` (mock LLM responses)
- Create `tests/testthat/helper-setup.R`:
  - `create_temp_db()` -> in-memory DB.
  - `mock_llm_call()` -> deterministic responses.
  - Sample narrative tibble.

## 6. Mocking Strategy
- Use `testthat::local_mock()` or `with_mocked_bindings()` to swap:
  - `call_llm()` (return canned responses + token usage)
  - `Sys.info()`, `Sys.time()` as needed
  - `httr2::req_perform()` (if mocking at HTTP layer)

## 7. Run & Document
- Update README “Testing” section with new commands & env gates.
- Document env vars (e.g. `RUN_SMOKE_TESTS`) in `tests/README.md`.
- Optional: add GitHub Actions workflow to run `Rscript tests/testthat.R`.

## 8. Cleanup Legacy Tests
- Move legacy tests to `tests/archive/` or delete after confirming coverage.
- Remove redundant shell scripts (`test_phase1.sh`, `validate_phase1.sh`) if replaced.

## 9. Timeline (estimate)
1. Fixtures/helpers scaffolding – ½ day.
2. Module tests (loader/schema/logger) – 1 day.
3. Orchestrator smoke test & script coverage – ½ day.
4. Cleanup harness + docs – ½ day.
5. Stabilize (run tests, fix flakiness) – ½ day.
6. Optional CI + guarding live tests – ½ day.

## 10. Validation Checklist
- `Rscript tests/testthat.R` exits 0 (default).
- `RUN_SMOKE_TESTS=1 Rscript tests/testthat.R` passes (gated tests).
- Manual QA (optional): run an experiment with mocked LLM to confirm end-to-end.
