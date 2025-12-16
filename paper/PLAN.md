# Paper Plan and TODOs

**Project**: IPV Detection in NVDRS Suicide Narratives

**Paper direction (locked)**: Production-scale descriptive analysis of **LLM-detected IPV indicators** in NVDRS suicide narratives, with validated performance on the existing labeled test dataset presented as supporting evidence (not the primary claim).

**Key principle**: Keep a strict separation between:

- **Descriptive production outputs** (full cohort; unlabeled): detection rates and patterns are *not* prevalence or accuracy.
- **Validated performance** (labeled test dataset): precision/recall/F1 (with clear config).

## Core Evidence Sources

**Production descriptive report (primary evidence)**
- `docs/analysis/20251107-production_report_v2.html`

**Model selection + validation artifacts (supporting evidence)**
- Figures: `docs/figures/figure1_model_performance.*`, `figure2_temperature_impact.*`, `figure3_precision_recall.*`, `figure4_efficiency_performance.*`
- Tables: `docs/tables/table1_model_performance.*`, `docs/tables/table2_top_experiments.*`

**Manuscript draft**
- `paper/manuscript.qmd`

## Planned Main Figures/Tables (Target Set)

### Must-have (main text)

1. **Cohort completeness**: incident-level availability (both CME+LE vs CME-only vs LE-only)
2. **Detection rate summary**: narrative-level and incident-level detected rates; stratified by narrative type and completeness
3. **Confidence distributions**: overall + stratified by detection outcome and narrative type
4. **Data quality context**: placeholder/brief narrative prevalence and association with detection

### Supporting (main text or supplement)

5. **Model/prompt selection summary**: existing `figure1`, `figure2`, `table2` (tie to chosen production configuration)
6. **Operational feasibility**: existing `figure4` + token/time distributions (from DB logs)

### Nice-to-have (space permitting)

- Temporal trends (year) for detection patterns
- Geographic variation (state) with appropriate interpretation/suppression decisions
- Indicator taxonomy summary (top extracted indicators among detected incidents)

## Validation Extension Plan (Production Distribution)

**Goal**: Estimate incident-level performance in the production distribution.

**Unit**: ~100 **incidents** (review both CME+LE narratives when available).

**Sampling strata** (initial proposal):

- 50 predicted incident-level positive / 50 predicted incident-level negative
- Within each label, stratify by incident completeness (both vs CME-only vs LE-only)
- Oversample low-confidence predictions within each label where feasible

**Outputs**:

- Incident-level precision/recall/F1 with uncertainty estimates
- Error analysis themes (linked to indicator taxonomy and data quality)

## TODO List (for future sessions)

### High priority

1. Lock descriptive-forward claims and terminology ("LLM-detected IPV indicators")
2. Audit existing artifacts in `docs/figures/` and `docs/tables/` for inclusion and caption plan
3. Map production report outputs to the planned main figures/tables (identify which already exist in HTML vs need regeneration)
4. Draft manuscript sections: Introduction, Methods, Production Descriptive Results, Discussion
5. Specify incident-level manual review protocol (annotation guide, adjudication, strata)

### Medium priority

6. Plan supplemental materials (prompt taxonomy, indicator definitions, exemplar de-identified snippets if allowed)
7. Create/refresh production descriptive figures/tables (completeness, rates, confidence, data quality, tokens/latency)
8. Assemble validated test-set performance artifacts as supporting results (PR curve, model selection, top experiments)

### Low priority

9. Render check for `paper/manuscript.qmd` (ensure no missing paths; defer full styling)
