# 20251005-Compendium Structure

**Project Type:** Research Compendium - LLM-based IPV detection in NVDRS suicide narratives

**Design Philosophy:** Reproducible research, not distributable software package. Functions accessed via `source()`, not `library()`.

---

## Directory Structure Overview

```
IPV_detection_in_NVDRS/
├── R/                          # Core modular functions (one function per file)
│   ├── legacy/                 # Archived code, reference only
│   └── *.R                     # Active functions
├── scripts/                    # Entry points and orchestration
│   ├── run_experiment.R        # Main experiment runner
│   ├── view_experiment.R       # Results viewer
│   └── *.sh                    # Utility shell scripts
├── configs/                    # Configuration files
│   ├── experiments/            # YAML experiment definitions
│   └── prompts/                # External prompt templates
├── tests/                      # Test suite
│   ├── testthat/               # Unit tests (207 tests)
│   └── integration/            # Integration tests
├── data/                       # Data storage (git-ignored)
│   ├── experiments.db          # SQLite database
│   └── synthetic_narratives.csv # Example data for reviewers
├── analysis/                   # Analysis notebooks and reports
│   ├── *.Rmd                   # Reproducible analysis notebooks
│   └── *.sh                    # Analysis execution scripts
├── docs/                       # Documentation (YYYYMMDD- prefix)
│   ├── 20251005-*.md           # Publication readiness docs
│   └── *.md                    # Other documentation
├── benchmark_results/          # Exported results (git-ignored)
├── logs/                       # Experiment logs (git-ignored)
├── supplementary_materials/    # Journal submission package
├── .env                        # Environment variables (git-ignored)
├── .env.example                # Environment variable template
├── .gitignore                  # Git ignore patterns
├── renv.lock                   # Dependency lock file
├── DESCRIPTION                 # R package metadata (minimal)
├── LICENSE                     # License file
├── CITATION.cff                # Citation metadata
└── README.md                   # Main project documentation
```

---

## Core Components

### R/ - Modular Functions Layer

**Purpose:** Core building blocks for LLM interaction, data processing, and experiment management.

**Key Files:**
- `call_llm.R` - LLM API interface (OpenAI, Anthropic)
- `config_loader.R` - YAML configuration loading
- `experiment_logger.R` - Result logging and tracking
- `db_config.R` - Database connection management
- `parse_llm_result.R` - Response parsing and JSON repair

**Usage Pattern:** Functions are sourced directly, not loaded as a package.
```r
source("R/call_llm.R")
source("R/config_loader.R")
result <- call_llm(model, prompt)
```

### scripts/ - Experiment Orchestration Layer

**Purpose:** High-level workflows that orchestrate modular functions using YAML configurations.

**Key Files:**
- `run_experiment.R` - Main experiment execution engine
- `view_experiment.R` - Results visualization and analysis
- `sync_sqlite_to_postgres.sh` - Database synchronization

**Design Principle:** Scripts control loops, parallelization, error handling. R functions are minimal building blocks.

### configs/ - Configuration Management

**Purpose:** Externalize all experiment parameters for reproducibility.

**Structure:**
- `experiments/` - YAML files defining complete experiments
- `prompts/` - Reusable prompt templates

**Example Experiment Config:**
```yaml
experiment_name: "exp_037_baseline_v4_t00_medium"
text_model: "gpt-4o-mini-2024-07-18"
extraction_model: null
prompt_version: "v4"
temperature: 0.0
```

---

## Two-Layer Architecture

### Layer 1: Modular Functions (R/)
- **Single responsibility:** One function per file
- **Stateless:** No global variables or side effects
- **Testable:** 207 unit tests with full coverage
- **Reusable:** Can be combined in different workflows

### Layer 2: Experiment Orchestration (scripts/)
- **YAML-driven:** All parameters externalized
- **Parallel execution:** Multi-core processing support
- **Error handling:** Graceful degradation and logging
- **Reproducible:** Full experiment tracking and provenance

**Communication Pattern:**
```
YAML Config → Script → Modular Functions → Results → Database
```

---

## Data Flow Architecture

### Input Layer
```
NVDRS Narratives → data_loader.R → Standardized Format
                      ↓
Prompt Templates → build_prompt.R → Formatted Prompts
```

### Processing Layer
```
Formatted Prompts → call_llm.R → LLM Responses
                      ↓
LLM Responses → parse_llm_result.R → Structured Data
```

### Storage Layer
```
Structured Data → experiment_logger.R → SQLite/PostgreSQL
                      ↓
Config/Metadata → db_schema.R → Experiment Tracking
```

### Analysis Layer
```
Database → experiment_queries.R → Results
                      ↓
Results → analysis/*.Rmd → Figures/Tables
```

---

## Reproducibility Features

### Configuration Management
- **YAML-based:** All parameters externalized
- **Version controlled:** Config changes tracked in git
- **Validated:** Schema validation for all configs
- **Environment-aware:** Supports dev/prod environments

### Experiment Tracking
- **Unique IDs:** Each experiment gets identifier
- **Full provenance:** Config, parameters, timestamps stored
- **Result logging:** Per-narrative results with metadata
- **Performance metrics:** Token usage, runtime tracking

### Dependency Management
- **renv lockfile:** Exact package versions specified
- **Environment isolation:** No system-wide package dependencies
- **Reproducible builds:** Same results across machines

---

## Database Architecture

### Primary Storage: SQLite
- **File:** `data/experiments.db`
- **Purpose:** Local development and testing
- **Schema:** Experiments and narratives tables
- **Advantages:** No external dependencies, portable

### Mirror Storage: PostgreSQL
- **Purpose:** Dashboards and advanced analytics
- **Sync:** Automated sync from SQLite
- **Connection:** Configured via environment variables
- **Optional:** System works without PostgreSQL

### Schema Design
```sql
experiments:
  - experiment_id (PK)
  - experiment_name
  - config (JSON)
  - metrics (JSON)
  - created_at
  - completed_at

narratives:
  - narrative_id (PK)
  - experiment_id (FK)
  - text_content
  - prediction
  - confidence
  - token_usage
  - created_at
```

---

## Testing Architecture

### Unit Tests (tests/testthat/)
- **207 tests** covering all active functions
- **Fast execution:** No external API calls
- **Comprehensive coverage:** Edge cases and error conditions
- **Continuous integration:** Automated testing on changes

### Integration Tests (tests/integration/)
- **End-to-end workflows:** Complete experiment execution
- **Database testing:** Real SQLite operations
- **API mocking:** Simulated LLM responses
- **Performance testing:** Large dataset processing

### Test Execution
```bash
# Full test suite
Rscript -e "testthat::test_dir('tests/testthat')"

# Integration tests only
Rscript tests/integration/run_integration_tests.R
```

---

## Analysis Workflow

### Notebook Structure
- **YYYYMMDD- prefix:** All analysis files dated
- **Reproducible:** Parameterized from configs
- **Self-contained:** Generate figures/tables independently
- **Version controlled:** Full analysis provenance

### Key Analysis Types
- **Experiment comparison:** Model/prompt performance
- **Error analysis:** Failure mode investigation
- **Validation metrics:** Accuracy assessment
- **Paper figures:** Reproducible publication graphics

---

## Publication Readiness Features

### Reviewer Accessibility
- **Synthetic data:** Test without NVDRS access
- **Demo workflow:** Quick validation script
- **Environment setup:** One-command installation
- **Clear documentation:** Step-by-step instructions

### Supplementary Materials
- **Complete repository:** All code and data
- **Reproducible analyses:** Generate all paper figures
- **Ethical documentation:** IRB and data use considerations
- **Citation metadata:** Standard academic citation formats

### Quality Assurance
- **Code review:** All changes reviewed and tested
- **Documentation:** Complete function and workflow docs
- **Version control:** Full git history with tags
- **License:** Clear usage terms for research

---

## Usage Patterns

### For Researchers (Primary Audience)
```bash
# Clone and set up
git clone <repository>
cd IPV_detection_in_NVDRS
renv::restore()
cp .env.example .env
# Edit .env with API keys

# Run demo with synthetic data
Rscript scripts/demo_workflow.R

# Run full experiment
Rscript scripts/run_experiment.R configs/experiments/exp_037.yaml

# View results
Rscript scripts/view_experiment.R <experiment_id>
```

### For Developers (Secondary Audience)
```bash
# Run tests
Rscript -e "testthat::test_dir('tests/testthat')"

# Add new function
# Create R/new_function.R
# Add tests in tests/testthat/test-new_function.R
# Update documentation

# Run integration tests
Rscript tests/integration/run_integration_tests.R
```

---

## Maintenance Considerations

### Backward Compatibility
- **Config schema:** Stable format with migration path
- **Function signatures:** No breaking changes without version bump
- **Database schema:** Versioned with migration scripts

### Extensibility
- **New LLM providers:** Add to call_llm.R interface
- **New prompt templates:** Add to configs/prompts/
- **New metrics:** Add to analysis notebooks
- **New analyses:** Create dated Rmd files

### Performance
- **Parallel processing:** Multi-core execution support
- **Connection pooling:** Database connection reuse
- **Batch operations:** Efficient API usage
- **Caching:** Avoid redundant computations