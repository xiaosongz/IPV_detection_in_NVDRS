# LLM-based Intimate Partner Violence Detection in NVDRS Suicide Narratives

**Research Compendium for Peer-Reviewed Publication**

This repository contains the complete code and data for detecting intimate partner violence (IPV) in suicide narratives from the National Violent Death Reporting System (NVDRS) using large language models (LLMs).

## 🎯 Research Question

Can LLMs accurately detect intimate partner violence as a contributing factor in suicide narratives from law enforcement and medical examiner reports?

## 📋 Quick Start for Reviewers

```bash
# 1. Clone repository
git clone <repository-url>
cd IPV_detection_in_NVDRS

# 2. Set up environment (requires R 4.5+)
Rscript -e "options(repos = c(CRAN = 'https://cloud.r-project.org/')); renv::restore()"

# 3. Configure environment variables
cp .env.example .env
# Edit .env with your API keys (optional for demo)

# 4. Run demonstration (5 minutes, no API keys required)
Rscript scripts/demo_workflow.R

# 5. Production smoke test (6-10 minutes, validates pipeline)
bash scripts/run_smoke_test.sh

# 6. View results
Rscript scripts/view_experiment.R <experiment_id_from_demo>
```

## 🏗️ System Architecture

This research compendium uses a **two-layer architecture**:

### Layer 1: Modular Functions (`R/`)
Core building blocks for LLM interaction, data processing, and experiment management. Each function is in its own file and accessed via `source()`.

### Layer 2: Experiment Orchestration (`scripts/`)
YAML-driven workflows that orchestrate modular functions using configurable parameters.

```
YAML Config → Script → Modular Functions → Results → Database
```

## 🏭 Production Infrastructure

The repository includes production-scale processing capabilities for handling 20K+ suicide narratives with robust error handling and progress tracking.

### Production Features
- **Resumable Experiments**: Pause and resume large-scale runs without losing progress
- **Progress Monitoring**: Real-time ETA calculations and batch processing updates
- **Data Integrity**: MD5 checksums, deduplication, and idempotent processing
- **Error Recovery**: Automatic retry mechanisms and graceful degradation
- **Database Mirroring**: SQLite to PostgreSQL synchronization for analytics

### Production Workflow
```bash
# 1. Production smoke test (6-10 minutes)
bash scripts/run_smoke_test.sh

# 2. Full production run (24-35 hours for 20K narratives)
bash scripts/run_production_20k.sh

# 3. Resume interrupted runs
bash scripts/resume_experiment.sh --db data/production_20k.db

# 4. Monitor production progress
Rscript scripts/exploratory/check_production_progress.R

# 5. Data quality analysis
Rscript scripts/exploratory/detailed_data_quality_analysis.R
```

### Production Database
- **Enhanced Schema**: Progress tracking, ETA calculations, PID locks
- **Batch Processing**: Configurable batch sizes for memory efficiency
- **Checkpoint System**: Automatic state persistence for resumability
- **Production Configuration**: Separate from test database for safety

## 📁 Repository Structure

```
IPV_detection_in_NVDRS/
├── R/                          # Core modular functions
│   ├── call_llm.R             # LLM API interface
│   ├── config_loader.R        # YAML configuration loading
│   ├── experiment_logger.R    # Result logging and tracking
│   ├── run_benchmark_core.R   # Enhanced with resumable runs
│   └── [10+ more active files]
├── R/legacy/                   # Archived code (737+ lines)
├── scripts/                    # Entry points and orchestration
│   ├── run_experiment.R       # Main experiment runner
│   ├── demo_workflow.R        # Quick demo for reviewers
│   ├── view_experiment.R      # Results viewer
│   ├── run_production_20k.sh  # Production 20k case processing
│   ├── resume_experiment.sh   # Resumable experiment management
│   ├── run_smoke_test.sh      # Quick validation testing
│   ├── sync_sqlite_to_postgres.sh # Database mirroring
│   ├── exploratory/           # Data quality analysis tools
│   └── sql/                   # Database schema scripts
├── configs/                    # Configuration files
│   ├── experiments/           # 52+ YAML experiment definitions
│   │   └── archive/           # Archived test configurations
│   └── prompts/               # Reusable prompt templates
├── data/                       # Data storage
│   ├── synthetic_narratives.csv # 30 example narratives for testing
│   ├── production_20k.db      # Production database (git-ignored)
│   └── experiments.db         # Test database (created automatically)
├── tests/                      # Comprehensive test suite
│   ├── testthat/              # Unit tests (200+ tests)
│   ├── integration/           # Integration tests
│   └── fixtures/              # Test data and databases
├── docs/                       # Documentation (YYYYMMDD- prefix)
│   ├── analysis/              # Analysis reports and notebooks
│   ├── communication/         # External communications
│   ├── figures/               # Generated figures
│   ├── tables/                # Generated tables
│   └── archive/               # Archived documentation
├── results/                    # Result exports
│   └── sample_responses/       # Sample LLM responses
└── .env.example                # Environment variable template
```

## 🔧 System Requirements

### Software
- **R 4.5+** with development tools
- **SQLite** (included with RSQLite package)
- **Git** for version control

### R Packages
All dependencies are managed through `renv` and automatically installed:
```r
renv::restore()  # Installs exact package versions
```

Key packages: `DBI`, `RSQLite`, `httr2`, `jsonlite`, `yaml`, `tibble`, `dplyr`, `readxl`, `testthat`

### Optional: LLM API Access
- **OpenAI API key** for GPT models
- **Anthropic API key** for Claude models  
- **Local LLM endpoint** for self-hosted models

## 📊 Data Access

### For Reviewers (No Restrictions)
The repository includes **synthetic example data** (`data/synthetic_narratives.csv`) with 30 realistic suicide narratives (15 IPV-positive, 15 IPV-negative). This allows full system testing without NVDRS access.

### For Production Use
**NVDRS Restricted Data** requires:
1. CDC/NVDRS data use agreement
2. IRB approval for research
3. Secure data handling environment
4. Completion of NVDRS training

**Data Format**: Excel files with columns:
- `IncidentID`: Unique incident identifier
- `NarrativeCME`: Medical examiner narrative
- `NarrativeLE`: Law enforcement narrative  
- `ipv_manual*`: Gold-standard IPV labels

## 🚀 Reproducible Workflow

### 1. Environment Setup
```bash
# Install exact package versions
renv::restore()

# Configure environment variables
cp .env.example .env
# Edit .env with your API keys
```

### 2. Run Experiments
```bash
# Demo with synthetic data (5 minutes)
Rscript scripts/demo_workflow.R

# Production smoke test (validation)
bash scripts/run_smoke_test.sh

# Full experiment with real data
Rscript scripts/run_experiment.R configs/experiments/exp_037_baseline_v4_t00_medium.yaml

# Production 20k case processing
bash scripts/run_production_20k.sh

# Resumable experiments (pause/resume capability)
bash scripts/resume_experiment.sh --db data/production_20k.db

# Batch experiments
bash scripts/run_experiments_037_051.sh
```

### 3. Analyze Results
```bash
# View experiment summary
Rscript scripts/view_experiment.R <experiment_id>

# Generate production analysis report
Rscript -e "rmarkdown::render('docs/analysis/20251030-production_report.Rmd')"

# Production progress monitoring
Rscript scripts/exploratory/check_production_progress.R

# Data quality analysis
Rscript scripts/exploratory/detailed_data_quality_analysis.R

# Historical analysis notebooks
Rscript -e "rmarkdown::render('docs/analysis/20251004-experiment_quality_report.Rmd')"
```

### 4. Testing
```bash
# Run full test suite (200+ tests)
Rscript -e "testthat::test_dir('tests/testthat')"

# Resumable run tests
Rscript tests/test_resumable_runs.R

# Integration tests only
Rscript tests/integration/run_integration_tests.R
```

## 🧪 Experiment Configuration

Experiments are defined in YAML files under `configs/experiments/`. Example structure:

```yaml
experiment:
  name: "Baseline v0.4.1 (T=0.0, Medium)"
  author: "researcher"
  notes: "Baseline detection with standard prompt"

model:
  name: "gpt-4o-mini"
  provider: "openai"
  api_url: "https://api.openai.com/v1/chat/completions"
  temperature: 0.0

prompt:
  version: "v0.4.1_baseline"
  system_prompt: | 
    ROLE: You are an expert trained to detect IPV...
  user_template: |
    TASK: Determine if the deceased was a victim of IPV...
    Narrative: <<TEXT>>

data:
  file: "data-raw/suicide_IPV_manuallyflagged.xlsx"

run:
  seed: 1024
  max_narratives: 1000000
  save_incremental: true
  batch_size: 50              # Production batch processing
  resume_enabled: true        # Enable resumable runs
  progress_tracking: true     # Enable ETA calculations
```

### Production Example
```yaml
experiment:
  name: "Production 20k Case Processing"
  author: "production_system"
  notes: "Full-scale IPV detection with resumable processing"

model:
  name: "mlx-community/gpt-oss-120b"
  provider: "local"
  api_url: "http://localhost:8080/v1/chat/completions"
  temperature: 0.2

data:
  file: "data/production_narratives.csv"

run:
  seed: 1024
  max_narratives: 20000
  batch_size: 100
  save_incremental: true
  resume_enabled: true
  progress_tracking: true
  database: "data/production_20k.db"
```

## 📈 Core Functions

### Main Interface
```r
# Primary detection function
detect_ipv <- function(text) {
  # Returns: {detected: TRUE/FALSE, confidence: 0-1}
}

# Load and validate configuration
config <- load_experiment_config("configs/experiments/exp_037.yaml")

# Run detection on narrative
result <- call_llm(config$model, prompt)
parsed <- parse_llm_result(result)
```

### Database Operations
```r
# Initialize experiment tracking
conn <- init_experiment_db()
experiment_id <- start_experiment(conn, config)

# Log results
log_narrative_result(conn, experiment_id, result)

# Query results
results <- get_experiment_results(conn, experiment_id)
```

## 📋 Available Experiments

The repository includes **52+ experiment configurations** testing:

- **Prompt versions**: Baseline, indicators, strict, context, chain-of-thought
- **Temperature settings**: 0.0, 0.2, 0.8 (low, medium, high variability)
- **Models**: GPT-4o-mini, local MLX models (mlx-community/gpt-oss-120b)
- **Reasoning levels**: Low, medium, high
- **Production configurations**: `exp_100_production_20k_indicators_t02_high.yaml`

### Key Experiment Types
- **exp_001-051**: Comparative analysis across models and prompts
- **exp_100-101**: Production-scale configurations and smoke tests
- **archived configurations**: Historical experiments in `configs/experiments/archive/`

See `configs/experiments/README.md` for complete list.

## 🧪 Testing and Validation

### Test Coverage
- **200+ unit tests** covering all active functions
- **Integration tests** for complete workflows
- **Performance tests** for large-scale processing
- **Resumable run tests** for production infrastructure
- **Error condition testing** for edge cases

### Enhanced Database Features
- **Production Schema**: Progress tracking, ETA calculations, PID locks
- **Data Integrity**: MD5 checksums, deduplication, idempotent processing
- **Batch Processing**: Configurable batch sizes for memory efficiency
- **Checkpoint System**: Automatic state persistence for resumability
- **PostgreSQL Mirroring**: Advanced analytics and dashboard support

### Validation Approach
- **Gold-standard comparison** against manually labeled NVDRS data
- **Cross-validation** across multiple prompt versions and models
- **Error analysis** of false positives/negatives
- **Computational efficiency** measurements
- **Production validation** through smoke testing and resumable runs

## 📊 Analysis and Results

### Reproducible Analysis Notebooks
All analysis notebooks use `YYYYMMDD-` prefix and are fully reproducible:

- `20251030-production_report.Rmd` - Complete 35K narrative production analysis
- `20251004-experiment_quality_report.Rmd` - Quality metrics and performance analysis
- `20251005-experiment_comparison.Rmd` - Model/prompt performance comparison
- `20251005-reproduce_paper_figures.Rmd` - Generate all paper figures/tables
- `20251005-validation_metrics.Rmd` - Accuracy metrics computation

### Production Analysis
- **Interactive Code Folding**: All code chunks collapsed by default with click-to-expand
- **Comprehensive Metrics**: Detection patterns, agreement analysis, confidence analysis
- **Data Quality Assessment**: Placeholder detection, narrative completeness analysis
- **Operational Performance**: Processing time, token usage, error rates

### Key Metrics
- **Precision**: True positives / (True positives + False positives)
- **Recall**: True positives / (True positives + False negatives)  
- **F1 Score**: Harmonic mean of precision and recall
- **Accuracy**: Overall correct classification rate

## 🔒 Security and Ethics

### Data Protection
- ✅ No sensitive NVDRS data in repository
- ✅ Synthetic data for reviewer testing
- ✅ Environment variables for API keys (never committed)
- ✅ Database files git-ignored
- ✅ Comprehensive input validation

### Ethical Considerations
- **IRB Approval**: Required for production use with real NVDRS data
- **Data Privacy**: All narratives anonymized before processing
- **Bias Awareness**: Models evaluated for demographic biases
- **Clinical Use**: Not intended for clinical decision-making
- **Transparency**: All methods and parameters fully documented

## 📄 Citation

**Software Citation**:
```
Zhang, X., et al. (2025). LLM-based Intimate Partner Violence Detection in NVDRS Suicide Narratives. 
R package version 0.1.0. https://github.com/username/IPV_detection_in_NVDRS
```

**Paper Citation** (when published):
```
[Paper citation will be added upon publication]
This repository contains supplementary materials for the peer-reviewed paper.
```

## 📜 License

This project is licensed under the **GPL-3 License** - see the [LICENSE](LICENSE) file for details.

**Research Use**: This software is provided for research purposes only. Not intended for clinical use or decision-making.

## 🤝 Contributing

This repository is designed as **research compendium** for publication. For questions or issues:

1. **Reviewers**: Please use the demo workflow (`scripts/demo_workflow.R`) for testing
2. **Researchers**: See `docs/20251005-publication_task_list.md` for development guidelines
3. **Issues**: Open an issue on GitHub with detailed description

## 📞 Support

### For Reviewers
- **Demo**: Run `Rscript scripts/demo_workflow.R` (5 minutes, no API keys required)
- **Production Validation**: Run `bash scripts/run_smoke_test.sh` (6-10 minutes)
- **Documentation**: See `docs/` directory with `YYYYMMDD-` prefix
- **Testing**: 200+ tests available via `Rscript -e "testthat::test_dir('tests/testthat')"`

### For Researchers
- **Configuration**: See `configs/experiments/` for available experiments
- **Production**: Use production scripts for large-scale processing
- **Analysis**: See `docs/analysis/` directory for reproducible notebooks
- **Implementation**: See `docs/FINAL_PRODUCTION_IMPLEMENTATION_AND_PROGRESS.md`

## 📚 Documentation Structure

All documentation files use `YYYYMMDD-` prefix for versioning:

### Production Documentation
- `FINAL_PRODUCTION_IMPLEMENTATION_AND_PROGRESS.md` - Production infrastructure status
- `PRODUCTION_20K_STATUS.md` - 20K case processing implementation status

### Analysis and Results
- `analysis/20251030-production_report.Rmd` - Complete production analysis with code folding
- `analysis/20251004-experiment_quality_report.Rmd` - Quality metrics and validation

### Historical Documentation (archived)
- `20251005-publication_task_list.md` - Complete publication readiness checklist
- `20251005-code_inventory.md` - Function categorization and dependencies
- `20251005-compendium_structure.md` - Repository architecture explanation
- `20251005-database_schema.md` - Database structure documentation

## 🔮 Future Development

This repository represents a **snapshot** of research for publication. Future versions may include:

- Additional LLM providers and models
- Enhanced prompt engineering techniques
- Multi-lingual support
- Real-time processing capabilities
- Clinical decision support integration

---

**Last Updated**: October 30, 2025
**Version**: 1.0.0 (Production Ready)
**Status**: Production Infrastructure Complete - Peer Review Welcome