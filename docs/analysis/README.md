# Analysis Directory

This directory contains analysis reports and R Markdown documents for experiment quality assessment.

## Reports

### 20251004-experiment_quality_report

**Comprehensive IPV Detection Experiment Quality Report**

- **Source**: `20251004-experiment_quality_report.Rmd`
- **Output**: `20251004-experiment_quality_report.html` (1.0 MB, interactive)
- **Data Source**: PostgreSQL database (experiments and narrative_results tables)

**Contents**:
1. Executive Summary
2. Experiment Overview (status distribution, model usage)
3. Performance Analysis (accuracy, precision, recall, F1, confusion matrix)
4. Prompt Quality Analysis (prompt versions, template characteristics)
5. Temperature & Configuration Analysis
6. Efficiency Analysis (runtime, token usage)
7. Error Pattern Analysis (top/bottom performers)
8. Recommendations (prompt engineering, future experiments)
9. Data Quality Assessment
10. Conclusions

**Key Findings** (as of 2025-10-04):
- **36 total experiments** (28 completed, 77.8% completion rate)
- **11,201 narratives processed**
- **Average accuracy**: 93.0%
- **Average F1 score**: 0.692
- **Primary model**: mlx-community/gpt-oss-120b (33 experiments)
- **Main challenge**: Recall (67.2%) and False Negative rate

**How to Use**:
1. Open `20251004-experiment_quality_report.html` in a web browser
2. Use the floating table of contents to navigate sections
3. Click "Code" buttons to view R code for each analysis
4. All tables and statistics are generated directly from the database

**Regenerating the Report**:
```bash
cd analysis
Rscript -e "rmarkdown::render('20251004-experiment_quality_report.Rmd')"
```

**Requirements**:
- R packages: `RPostgres`, `DBI`, `dplyr`, `tidyr`, `stringr`, `knitr`, `rmarkdown`
- PostgreSQL database credentials in `.env` file (parent directory)
- Active connection to PostgreSQL database

## Database Connection

Reports automatically read credentials from `../.env` file:
```
PG_HOST=memini.lan
PG_PORT=5433
PG_USER=postgres
PG_PASSWORD=<password>
PG_DATABASE=postgres
```

## Future Reports

Additional analysis reports will be added to this directory following the naming convention:
`YYYYMMDD-descriptive_name.Rmd` → `YYYYMMDD-descriptive_name.html`

Suggested future reports:
- Model comparison analysis
- Prompt evolution tracking
- Longitudinal performance trends
- Cost/efficiency optimization analysis
- Error case deep-dive analysis
