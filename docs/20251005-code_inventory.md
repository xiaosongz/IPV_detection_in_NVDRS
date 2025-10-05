# 20251005-Code Inventory

**Project Type:** Research Compendium - LLM-based IPV detection in NVDRS suicide narratives

**Architecture:** Two-layer design
1. **Modular Functions** (`R/`) - Core building blocks, one function per file
2. **Experiment Orchestration** (`scripts/`) - YAML-driven workflows using modular functions

---

## Active Functions (R/)

### Core LLM Functions
- **`call_llm.R`** - Primary LLM API interface
  - Supports OpenAI and Anthropic models
  - Handles rate limiting and retries
  - Token usage tracking

- **`parse_llm_result.R`** - Parse LLM responses into structured data
  - JSON extraction and repair
  - Confidence score parsing
  - Error handling for malformed responses

- **`build_prompt.R`** - Construct prompts from templates and data
  - Template substitution
  - Narrative formatting
  - Context management

### Configuration & Data Management
- **`config_loader.R`** - Load and validate YAML experiment configs
  - Schema validation
  - Default value handling
  - Environment variable substitution

- **`data_loader.R`** - Load narrative data from various sources
  - CSV/JSON support
  - Data validation
  - Batch processing

- **`db_config.R`** - Database connection management
  - SQLite and PostgreSQL support
  - Connection pooling
  - Environment-based configuration

### Database Operations
- **`db_schema.R`** - Database schema definition and migration
  - Table creation
  - Index management
  - Schema versioning

- **`experiment_queries.R`** - SQL queries for experiment data
  - Results retrieval
  - Aggregation queries
  - Performance metrics

- **`experiment_logger.R`** - Log experiment execution and results
  - Structured logging
  - Performance tracking
  - Error capture

### Experiment Core
- **`run_benchmark_core.R`** - Core benchmark execution logic
  - Batch processing
  - Parallel execution
  - Result aggregation

### Utilities
- **`repair_json.R`** - JSON repair utilities
  - Malformed JSON fixing
  - Fallback parsing strategies
  - Error recovery

- **`IPVdetection-package.R`** - Package documentation stub
  - Roxygen documentation
  - Package metadata (minimal, as this is not a loadable package)

---

## Legacy Functions (R/legacy/)

**Status:** Archived for reference only. Do not use in new code.

### Core Legacy Functions
- **`call_llm_batch.R`** - Batch LLM calling (replaced by parallel execution in run_benchmark_core.R)
- **`experiment_utils.R`** - General experiment utilities (functionality split across multiple active files)
- **`experiment_analysis.R`** - Analysis functions (moved to analysis/ notebooks)
- **`store_llm_result.R`** - Result storage (integrated into experiment_logger.R)

### Database & Utilities
- **`db_utils.R`** - Database utilities (replaced by db_config.R and experiment_queries.R)
- **`utils.R`** - General utilities (functionality distributed across active files)

### Setup & Documentation
- **`0_setup.R`** - Environment setup (replaced by renv and .env management)
- **`README.md`** - Legacy documentation (superseded by main repository README)
- **`metrics.R`** - Metrics computation (integrated into analysis notebooks)

---

## Function Dependencies

### Core Dependencies
```
config_loader → data_loader → build_prompt
     ↓              ↓              ↓
db_config ← call_llm ← parse_llm_result
     ↓              ↓              ↓
experiment_logger ← run_benchmark_core → experiment_queries
     ↓                                      ↓
db_schema ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
```

### Optional Dependencies
- **`repair_json.R`** - Used by parse_llm_result.R for error recovery
- **`IPVdetection-package.R`** - Documentation only, no runtime dependencies

---

## Data Flow

```
YAML Config → config_loader.R
     ↓
Narrative Data → data_loader.R
     ↓
Prompt Template → build_prompt.R
     ↓
LLM API → call_llm.R
     ↓
Response → parse_llm_result.R
     ↓
Structured Data → experiment_logger.R
     ↓
Database ← db_schema.R + experiment_queries.R
```

---

## Usage Patterns

### Research Compendium Access Pattern
```r
# Functions are accessed via source(), not library()
source("R/call_llm.R")
source("R/config_loader.R")
source("R/experiment_logger.R")

# Direct function calls
config <- load_config("configs/experiments/exp_037.yaml")
result <- call_llm(config$text_model, prompt)
log_result(config, result)
```

### Experiment Orchestration Pattern
```r
# scripts/run_experiment.R orchestrates the full workflow
# Uses modular functions from R/ directory
# YAML-driven configuration
# SQLite/PostgreSQL storage
```

---

## Migration History

### From Legacy to Current
- **Batch processing** → Distributed parallel execution
- **Monolithic utilities** → Specialized single-purpose functions
- **Direct database access** → Configured connection management
- **Manual result storage** → Structured logging system

### Key Improvements
1. **Separation of concerns** - One function per file
2. **Configurable backends** - SQLite + PostgreSQL support
3. **Error handling** - Graceful degradation and retry logic
4. **Reproducibility** - Full experiment tracking and logging
5. **Performance** - Parallel execution and connection pooling

---

## Quality Assurance

### Test Coverage
- **207 tests** covering all active functions
- **Integration tests** for complete workflows
- **Error condition testing** for edge cases
- **Performance tests** for large-scale processing

### Documentation Standards
- **Roxygen comments** for all functions
- **Type hints** via roxygen @param tags
- **Usage examples** where appropriate
- **Error documentation** for failure modes

---

## Future Considerations

### Potential Extensions
- **Additional LLM providers** via call_llm.R interface
- **Custom metrics** via analysis notebooks
- **Advanced prompt engineering** via build_prompt.R
- **Database backends** via db_config.R abstraction

### Maintenance Notes
- **No breaking changes** to function signatures without version bump
- **Backward compatibility** maintained for experiment configs
- **Legacy functions** preserved for reference but not used
- **Test suite** must pass before any changes to core functions
``````
