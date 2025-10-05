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

# 5. View results
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

## 📁 Repository Structure

```
IPV_detection_in_NVDRS/
├── R/                          # Core modular functions
│   ├── call_llm.R             # LLM API interface
│   ├── config_loader.R        # YAML configuration loading
│   ├── experiment_logger.R    # Result logging and tracking
│   └── [8 more active files]
├── scripts/                    # Entry points and orchestration
│   ├── run_experiment.R       # Main experiment runner
│   ├── demo_workflow.R        # Quick demo for reviewers
│   └── view_experiment.R      # Results viewer
├── configs/                    # Configuration files
│   ├── experiments/           # 51 YAML experiment definitions
│   └── prompts/               # Reusable prompt templates
├── data/                       # Data storage
│   ├── synthetic_narratives.csv # 30 example narratives for testing
│   └── experiments.db         # SQLite database (created automatically)
├── tests/                      # Test suite (207 tests)
├── analysis/                   # Reproducible analysis notebooks
├── docs/                       # Documentation (YYYYMMDD- prefix)
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

# Full experiment with real data
Rscript scripts/run_experiment.R configs/experiments/exp_037_baseline_v4_t00_medium.yaml

# Batch experiments
bash scripts/run_experiments_037_051.sh
```

### 3. Analyze Results
```bash
# View experiment summary
Rscript scripts/view_experiment.R <experiment_id>

# Generate analysis notebooks
Rscript -e "rmarkdown::render('analysis/20251005-experiment_comparison.Rmd')"
```

### 4. Testing
```bash
# Run full test suite (207 tests)
Rscript -e "testthat::test_dir('tests/testthat')"

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

The repository includes **51 experiment configurations** testing:

- **Prompt versions**: Baseline, indicators, strict, context, chain-of-thought
- **Temperature settings**: 0.0, 0.2, 0.8 (low, medium, high variability)
- **Models**: GPT-4o-mini, local MLX models
- **Reasoning levels**: Low, medium, high

See `configs/experiments/README.md` for complete list.

## 🧪 Testing and Validation

### Test Coverage
- **207 unit tests** covering all active functions
- **Integration tests** for complete workflows
- **Performance tests** for large-scale processing
- **Error condition testing** for edge cases

### Validation Approach
- **Gold-standard comparison** against manually labeled NVDRS data
- **Cross-validation** across multiple prompt versions and models
- **Error analysis** of false positives/negatives
- **Computational efficiency** measurements

## 📊 Analysis and Results

### Reproducible Analysis Notebooks
All analysis notebooks use `YYYYMMDD-` prefix and are fully reproducible:

- `20251005-experiment_comparison.Rmd` - Model/prompt performance comparison
- `20251005-error_analysis.Rmd` - Failure mode analysis  
- `20251005-reproduce_paper_figures.Rmd` - Generate all paper figures/tables
- `20251005-validation_metrics.Rmd` - Accuracy metrics computation

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
- **Documentation**: See `docs/` directory with `YYYYMMDD-` prefix
- **Testing**: 207 tests available via `Rscript -e "testthat::test_dir('tests/testthat')"`

### For Researchers  
- **Configuration**: See `configs/experiments/` for available experiments
- **Analysis**: See `analysis/` directory for reproducible notebooks
- **Extension**: See `docs/20251005-code_inventory.md` for function documentation

## 📚 Documentation Structure

All documentation files use `YYYYMMDD-` prefix for versioning:

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

**Last Updated**: October 5, 2025  
**Version**: 0.1.0 (Pre-publication)  
**Status**: Publication Ready - Peer Review Welcome