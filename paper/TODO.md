# IPV Detection Methods Paper - TODO & Roadmap

## High-Level Phases

```
Phase 1: Foundation (Week 1-2)
    └── Structure, outline, literature review
Phase 2: Methods & Results (Week 2-4)
    └── Core writing, figure integration
Phase 3: Polish & Review (Week 4-6)
    └── Internal review, revisions
Phase 4: Submission (Week 6+)
    └── Journal selection, formatting, submit
```

---

## Phase 1: Foundation

### 1.1 Setup
- [x] Create paper directory structure
- [x] Create manuscript template (Quarto)
- [ ] Set up references.bib with initial citations
- [ ] Link/copy existing figures from `docs/figures/`
- [ ] Review Andrea's pre-Thanksgiving report for content

### 1.2 Literature Review
- [ ] Search for existing LLM applications in:
  - [ ] Death investigation / forensic narratives
  - [ ] IPV detection (any modality)
  - [ ] NVDRS data analysis
  - [ ] NLP in public health surveillance
- [ ] Identify gap: No LLM-based IPV detection in death narratives
- [ ] Draft Introduction background paragraphs
- [ ] Compile references.bib (target: 30-50 citations)

### 1.3 Outline Review
- [ ] Review manuscript.qmd outline with Andrea
- [ ] Get feedback from PIs on scope
- [ ] Finalize target journal (affects formatting)

---

## Phase 2: Methods & Results

### 2.1 Methods Section
- [ ] **Data Source**
  - [ ] NVDRS description and access
  - [ ] Narrative types (CME vs LE)
  - [ ] De-identification approach
  - [ ] IRB/ethics statement

- [ ] **LLM Approach**
  - [ ] Model selection rationale (local vs cloud)
  - [ ] Prompt engineering methodology
    - [ ] Document prompt versions (v0.1 → v0.3.2)
    - [ ] Indirect indicators approach
    - [ ] Temperature parameter selection
  - [ ] Binary classification design

- [ ] **Validation**
  - [ ] Gold standard creation (manual annotation)
  - [ ] Train/validation/test split
  - [ ] Metrics: F1, precision, recall, accuracy
  - [ ] Inter-rater reliability (if applicable)

- [ ] **Production Pipeline**
  - [ ] Resumable processing design
  - [ ] Quality controls (checksums, batched commits)
  - [ ] Scalability considerations

### 2.2 Results Section
- [ ] **Performance Metrics**
  - [ ] Overall F1: 0.8077
  - [ ] Precision/recall breakdown
  - [ ] Confidence score distribution

- [ ] **Experiment Comparisons**
  - [ ] Prompt version comparison (Figure 1)
  - [ ] Temperature impact (Figure 2)
  - [ ] Model comparison (if applicable)

- [ ] **Production Readiness**
  - [ ] Processing speed metrics
  - [ ] Error rates
  - [ ] Resource requirements

### 2.3 Figures & Tables
- [ ] Review existing figures for publication quality
- [ ] Figure 1: Model performance comparison
- [ ] Figure 2: Temperature impact analysis
- [ ] Figure 3: Precision-recall curves
- [ ] Figure 4: Efficiency vs performance
- [ ] Table 1: Dataset characteristics
- [ ] Table 2: Top experiment configurations
- [ ] Table 3: Performance comparison with baselines (if available)

---

## Phase 3: Polish & Review

### 3.1 Discussion Section
- [ ] Interpret key findings
- [ ] Compare to existing methods (traditional NLP, keyword matching)
- [ ] Implications for public health surveillance
- [ ] Limitations:
  - [ ] Single dataset (NVDRS)
  - [ ] Binary classification (no severity)
  - [ ] English only
  - [ ] Model availability/cost
- [ ] Future directions:
  - [ ] UM AI Toolkit integration (98% target)
  - [ ] Multi-label classification
  - [ ] Real-time surveillance

### 3.2 Abstract & Conclusion
- [ ] Write structured abstract (250-300 words)
- [ ] Write conclusion (highlight novelty and impact)

### 3.3 Supplementary Materials
- [ ] Full prompt text (all versions)
- [ ] Extended methods for validation
- [ ] Code availability statement
- [ ] Additional tables/figures

### 3.4 Internal Review
- [ ] Self-review and edit
- [ ] Andrea review (statistical methods)
- [ ] Anca review (data/NVDRS accuracy)
- [ ] PI review (scope, framing)
- [ ] Address all feedback

---

## Phase 4: Submission

### 4.1 Journal Selection
- [ ] Finalize target journal
- [ ] Review author guidelines
- [ ] Check formatting requirements
- [ ] Identify cover letter requirements

### 4.2 Final Preparation
- [ ] Format manuscript per journal guidelines
- [ ] Prepare cover letter
- [ ] Compile author information
- [ ] Conflict of interest statements
- [ ] Data availability statement
- [ ] Code availability statement (GitHub link)

### 4.3 Submit
- [ ] Submit manuscript
- [ ] Track submission status
- [ ] Respond to reviews

---

## Quick Reference: Key Metrics

| Item | Value |
|------|-------|
| Best Configuration | exp_012 |
| F1 Score | 0.8077 |
| Accuracy | ~95% |
| Prompt Version | v0.3.2_indicators |
| Temperature | 0.2 |
| Total Narratives | 35,312 |
| Test Coverage | 97/97 (100%) |

---

## Notes & Decisions Log

### 2025-12-15
- Created paper directory structure
- Initial TODO and manuscript template created
- Existing assets: 4 figures, 2 tables, figure reproduction Rmd

---

*Last Updated: 2025-12-15*
