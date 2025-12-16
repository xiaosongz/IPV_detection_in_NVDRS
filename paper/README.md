# IPV Detection Methods Paper

## Paper Focus

**Title (Working)**: Large Language Models for Automated Detection of Intimate Partner Violence in Death Investigation Narratives: A Methods Paper

**Type**: Methods/Technical Paper

**Target Journals** (to discuss with team):
- JAMIA (Journal of the American Medical Informatics Association)
- Journal of Biomedical Informatics
- PLOS ONE (Computational Biology)
- npj Digital Medicine

## Directory Structure

```
paper/
├── README.md              # This file
├── TODO.md                # Writing roadmap and task tracking
├── manuscript.qmd         # Main Quarto manuscript
├── references.bib         # Bibliography (to be created)
├── figures/               # Publication-ready figures
│   └── (symlink or copy from ../docs/figures/)
└── supplementary/         # Supplementary materials
    ├── prompts/           # Full prompt text
    ├── validation/        # Validation methodology details
    └── code_walkthrough/  # Code documentation for reviewers
```

## Existing Assets

The following assets are already available in the main repo:

### Figures (`../docs/figures/`)
- `figure1_model_performance.png/pdf` - Model performance comparison
- `figure2_temperature_impact.png/pdf` - Temperature parameter effects
- `figure3_precision_recall.png/pdf` - Precision-recall curves
- `figure4_efficiency_performance.png/pdf` - Efficiency vs performance tradeoffs

### Tables (`../docs/tables/`)
- `table1_model_performance.csv/tex` - Performance summary
- `table2_top_experiments.csv/tex` - Top experiment configurations

### Analysis Code (`../docs/analysis/`)
- `20251005-reproduce_paper_figures.Rmd` - Figure reproduction code

## Key Results to Highlight

| Metric | Value | Notes |
|--------|-------|-------|
| Best F1 Score | 0.8077 | exp_012 configuration |
| Accuracy | ~95% | On validation set |
| Dataset Size | 35,312 narratives | CME: 19,549, LE: 15,763 |
| Source Cases | 20,946 | Unique suicide cases |
| Test Coverage | 97/97 | 100% passing |

## Writing Workflow

1. Edit `manuscript.qmd` in RStudio or VS Code
2. Render with: `quarto render paper/manuscript.qmd`
3. Output formats: PDF, DOCX, HTML (configurable)

## Team Roles (TBD)

- **Xiaosong Zhang**: Lead author, methods development, implementation
- **Andrea Pangori**: Statistical validation, methodology review
- **Anca Tilea**: Data management, NVDRS expertise
- **[PIs]**: Conceptualization, supervision, review
