# Publication Readiness Plan: Research Compendium

**Model:** Research Compendium (Option B)
- Users clone repository and run scripts
- Functions are implementation details
- Published as supplementary material to paper
- Focus: Reproducibility over reusability

**Goal:** Enable reviewers and future researchers to reproduce findings and understand methodology.

---

## Phase 1: Scope & Architecture (Week 1)

### 1.1 Audit Current Codebase
**Task:** Categorize all R/ functions into:
- **Core detection** - The actual IPV detection logic (keep, document thoroughly)
- **Experiment infrastructure** - Database, logging, metrics (keep, document moderately)
- **Utilities** - Helper functions (keep if used, delete if orphaned)
- **Legacy** - R/legacy/ contents (document purpose or delete)

**Deliverable:** `docs/code_inventory.md` with function categorization and usage status

### 1.2 Define Research Compendium Structure
**Task:** Document the canonical structure following research compendium best practices
```
IPV_detection_in_NVDRS/
├── R/                      # All function definitions
├── scripts/                # Computational workflows (entry points)
├── configs/                # Experiment configurations
├── data/                   # Input data (restricted, document access)
├── results/                # Generated outputs (git-ignored, document structure)
├── docs/                   # Documentation and supplementary materials
├── tests/                  # Verification suite
├── analysis/               # Reproducible analysis notebooks
└── paper/                  # Manuscript and figures (optional)
```

**Deliverable:** `docs/compendium_structure.md` explaining each directory's role

### 1.3 Remove All Dead Code
**Task:**
- Use code coverage or static analysis to find unused functions
- Delete completely or move to `archive/` with explanation
- No orphaned code without documentation

**Deliverable:** Clean R/ directory with only actively-used code

---

## Phase 2: Core Documentation (Week 2)

### 2.1 Write Comprehensive README.md
**Structure:**
```markdown
# IPV Detection in NVDRS Suicide Narratives

## Purpose
What problem this solves, research question

## Citation
How to cite (placeholder until published)

## System Requirements
- R version (specify exact version)
- Required R packages (with versions)
- System dependencies (PostgreSQL, etc.)
- API access (OpenAI, Anthropic)

## Installation
git clone ...
R package installation
Environment setup (.env configuration)

## Data Access
NVDRS data is restricted. Instructions for approved researchers.
Example/synthetic data provided for testing.

## Reproducible Workflow
Step-by-step to reproduce paper findings:
1. Setup environment
2. Run experiments
3. Generate figures/tables
4. Validate against published results

## Repository Structure
Brief overview of directories

## License
Choose: GPL-3 (standard for research) or MIT

## Ethical Considerations
IRB approval, intended use, privacy protections

## Contact
Corresponding author, how to get help
```

**Deliverable:** Publication-quality README.md

### 2.2 Document All Scripts
**Task:** Add comprehensive header comments to every script in `scripts/`
```r
# scripts/run_experiment.R
#
# Purpose: Execute a single experiment from YAML config
# Usage: Rscript scripts/run_experiment.R configs/experiments/exp_037.yaml
# Inputs: YAML config file path
# Outputs: SQLite database entry, logs in logs/experiments/
# Dependencies: R/ functions, OpenAI API key in .env
# Expected runtime: ~30 minutes for 404 narratives
```

Create `scripts/README.md` documenting the complete workflow sequence.

**Deliverable:** Fully documented scripts/ with workflow README

### 2.3 Function-Level Documentation (Roxygen)
**Task:**
- Keep roxygen comments but don't worry about exports
- Focus on @param, @return, @examples, @details
- Examples should be runnable (use `\dontrun{}` for API calls)
- Regenerate .Rd files with `devtools::document()` for completeness

**Why keep .Rd files:** They render nicely in pkgdown site even if never loaded as library

**Deliverable:** Complete roxygen docs for all public-facing functions

---

## Phase 3: Reproducible Analysis (Week 3)

### 3.1 Create Synthetic Example Data
**Challenge:** Real NVDRS data is restricted

**Solution:**
- Generate realistic fake suicide narratives (100-200 examples)
- Include positive/negative IPV cases
- Save as `data/synthetic_narratives.csv`
- Document generation process
- Add disclaimer in README

**Deliverable:** `data/synthetic_narratives.csv` + generation script

### 3.2 Minimal Reproducible Workflow
**Task:** Create `scripts/demo_workflow.R` that:
1. Uses synthetic data
2. Runs detection on small sample
3. Stores results in SQLite
4. Generates basic metrics
5. Completes in <5 minutes

**Purpose:** Proves system works without NVDRS access

**Deliverable:** `scripts/demo_workflow.R` that anyone can run

### 3.3 Analysis Notebooks
**Task:** Create `analysis/` directory with:
- `01_experiment_comparison.Rmd` - Compare prompt/model performance
- `02_error_analysis.Rmd` - Analyze failure modes
- `03_reproduce_paper_figures.Rmd` - Generate all paper figures/tables
- `04_validation_metrics.Rmd` - Compute accuracy against gold standard

Use R Markdown for literate programming.

**Deliverable:** Reproducible analysis pipeline in analysis/

---

## Phase 4: Computational Environment (Week 4)

### 4.1 Dependency Management with renv
**Task:**
```r
renv::init()         # Capture current package versions
renv::snapshot()     # Lock dependencies
# Commit renv.lock to git
```

**Benefit:** Anyone can restore exact package versions with `renv::restore()`

**Alternative:** List exact versions in DESCRIPTION and README

**Deliverable:** `renv.lock` or detailed version documentation

### 4.2 Environment Variable Documentation
**Task:**
- Create `.env.example` with all required variables
- Document each variable's purpose
- Add setup instructions to README
- Never commit real `.env` to git

**Example:**
```bash
# .env.example
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
PG_CONN_STR=postgresql://user:pass@host:port/db
```

**Deliverable:** `.env.example` + setup documentation

### 4.3 Docker Container (Optional)
**If you want bulletproof reproducibility:**
- Create `Dockerfile` with exact R version + dependencies
- Include PostgreSQL setup
- Document docker-compose workflow

**Trade-off:** Adds complexity, but guarantees bit-for-bit reproducibility

**Deliverable:** Docker setup or decision to skip with rationale

---

## Phase 5: Data & Schema Documentation (Week 5)

### 5.1 Database Schema Documentation
**Task:** Create `docs/database_schema.md`
```markdown
# Database Schema

## experiments table
- Column definitions
- Data types
- Foreign keys
- Indexes

## narratives table
- Column definitions
- Relationships to experiments
- Token usage tracking

## Schema migrations
- How schema evolved
- Migration scripts (if any)

## Sync process
- SQLite → PostgreSQL sync
- Why both databases
- Sync script usage
```

**Deliverable:** Complete schema documentation

### 5.2 Data Provenance
**Task:** Document in `docs/data_provenance.md`
- NVDRS data source and access process
- Date range of narratives used
- Inclusion/exclusion criteria
- Gold-standard labeling process
- IRB approval number (if applicable)

**Deliverable:** Transparent data provenance documentation

### 5.3 Results Structure Documentation
**Task:** Document expected outputs
- Where experiments write results
- File naming conventions
- How to interpret logs
- Archival process for 60k run results

**Deliverable:** `docs/results_structure.md`

---

## Phase 6: Testing & Validation (Week 6)

### 6.1 Test Suite Documentation
**Task:** Create `tests/README.md`
```markdown
# Test Suite

## Running tests
testthat::test_dir('tests/testthat')
tests/integration/run_integration_tests.R

## Test coverage
Current coverage: X%
How to generate coverage report

## What's tested
- Core detection logic
- Database operations
- LLM parsing
- Configuration validation

## What's NOT tested and why
- Live API calls (mocked or integration tests only)
- 60k-scale performance (too expensive)
```

**Deliverable:** Test suite documentation

### 6.2 Validation Benchmark
**Task:** If you have gold-standard labels:
- Create `scripts/validate_against_gold_standard.R`
- Compute precision, recall, F1
- Document in `docs/validation_results.md`
- Make reproducible with synthetic or example data

**Deliverable:** Validation documentation + reproducible script

### 6.3 Known Limitations
**Task:** Create `docs/limitations.md`
- Model hallucination cases
- Edge cases that fail
- Computational cost constraints
- Generalizability concerns

**Transparency is critical for research.**

**Deliverable:** Honest limitations documentation

---

## Phase 7: Publication Metadata (Week 7)

### 7.1 CITATION File
**Task:** Create both formats:

`inst/CITATION`:
```r
citEntry(
  entry = "Unpublished",
  title = "LLM-based IPV Detection in NVDRS Suicide Narratives",
  author = personList(
    person("FirstName", "LastName", email = "email@inst.edu", role = c("aut", "cre"))
  ),
  year = "2025",
  note = "R package version 0.1.0",
  url = "https://github.com/username/IPV_detection_in_NVDRS"
)
```

`CITATION.cff` (GitHub standard):
```yaml
cff-version: 1.2.0
message: "If you use this software, please cite it as below."
title: "IPV Detection in NVDRS"
authors:
  - family-names: LastName
    given-names: FirstName
    orcid: https://orcid.org/0000-0000-0000-0000
```

**Update when paper is published.**

**Deliverable:** Both CITATION files

### 7.2 DESCRIPTION Cleanup
**Task:**
- Accurate title and description
- All authors with roles (aut, cre, ctb)
- All dependencies with minimum versions
- Remove unused dependencies
- License field

**Deliverable:** Clean DESCRIPTION file

### 7.3 Versioning & Changelog
**Task:**
- Start at `0.1.0` (pre-publication)
- Use semantic versioning
- Create `NEWS.md` tracking changes
- Tag git releases: `git tag v0.1.0`

**When to bump:**
- 0.1.0 → 0.2.0: Major experiment changes
- 0.2.0 → 1.0.0: Paper accepted/published
- 1.0.0 → 1.0.1: Bug fixes post-publication

**Deliverable:** Versioning scheme + NEWS.md

### 7.4 License Selection
**Common for research:**
- **GPL-3**: If you want derivatives to be open-source
- **MIT**: If you want maximum freedom for reuse
- **CC-BY-4.0**: For documentation/data (not code)

**Add:** `LICENSE` file + license headers in key files

**Deliverable:** LICENSE file

---

## Phase 8: Distribution & Archival (Week 8)

### 8.1 GitHub Repository Polish
**Checklist:**
- [ ] README renders correctly on GitHub
- [ ] Good .gitignore (no secrets, no data, no results)
- [ ] Topics/tags for discoverability ("nvdrs", "ipv-detection", "llm", "suicide-prevention")
- [ ] Repository description filled in
- [ ] Link to paper when published
- [ ] CONTRIBUTING.md if you want contributions (probably not)
- [ ] CODE_OF_CONDUCT.md (optional)

**Deliverable:** Publication-ready GitHub repo

### 8.2 Zenodo DOI
**Process:**
1. Link GitHub repo to Zenodo
2. Create release: `git tag v1.0.0 && git push --tags`
3. Zenodo automatically creates DOI
4. Add DOI badge to README
5. Cite DOI in paper

**Benefit:** Permanent archive, citable even if GitHub disappears

**Deliverable:** Zenodo DOI for repository

### 8.3 Supplementary Materials Package
**For journal submission:**
- Create `supplementary_materials/` directory
- Include: README, key scripts, synthetic data, analysis notebooks
- Package as .zip for submission
- Document relationship to GitHub repo

**Deliverable:** Supplementary materials bundle

### 8.4 Installation Testing
**Task:** Test on clean machine:
```bash
git clone https://github.com/username/IPV_detection_in_NVDRS
cd IPV_detection_in_NVDRS
# Follow README installation instructions
# Run demo_workflow.R
# Verify it works
```

**Find someone else to test (or use fresh VM).**

**Deliverable:** Verified installation instructions

---

## Phase 9: Paper Alignment (Ongoing)

### 9.1 Methods Section Consistency
**Ensure code matches paper:**
- Algorithm descriptions in methods match implementation
- Hyperparameters documented (temperature, max_tokens, etc.)
- Prompt versions correspond to experiments cited
- Metrics definitions match computation

**Deliverable:** Code-paper alignment checklist

### 9.2 Figures & Tables Reproducibility
**Every figure/table in paper should:**
- Have corresponding script in `analysis/`
- Use committed configs/data
- Be reproducible from command line
- Match published version exactly

**Deliverable:** `analysis/reproduce_paper.sh` that generates everything

### 9.3 Response to Reviewers
**Prepare for common requests:**
- "Can you try model X?" → Document how to add new models
- "What about prompt Y?" → Document how to add new prompts
- "Show me edge cases" → Have error analysis ready
- "Computational cost?" → Document in paper and code

**Deliverable:** Flexible, well-documented experiment framework

---

## Priority Timeline

### Must-Have (Before Submission)
- Phase 1: Scope & Architecture
- Phase 2: Core Documentation (README, scripts, functions)
- Phase 3.3: Analysis notebooks that reproduce paper results
- Phase 5.1: Database schema docs
- Phase 5.2: Data provenance
- Phase 7: Publication metadata (CITATION, LICENSE, versioning)
- Phase 9: Paper-code alignment

### Should-Have (Before Publication)
- Phase 3.1-3.2: Synthetic data and demo
- Phase 4.1-4.2: Dependency management and environment docs
- Phase 6: Testing and validation docs
- Phase 8.1-8.2: GitHub polish and Zenodo DOI

### Nice-to-Have (Post-Publication)
- Phase 4.3: Docker container
- Phase 8.3-8.4: Supplementary materials package
- pkgdown website
- Video walkthrough

---

## Quality Checklist

Before considering "publication ready," verify:

- [ ] Reviewer can clone repo and run analysis without contacting authors
- [ ] All paper figures/tables have reproducible source
- [ ] Dependencies explicitly versioned
- [ ] No hardcoded paths or credentials in code
- [ ] Synthetic data allows testing without NVDRS access
- [ ] README installation instructions tested on clean machine
- [ ] All functions used in paper have documentation
- [ ] Database schema matches what code expects
- [ ] License permits intended use
- [ ] Citation information complete
- [ ] Ethical considerations documented
- [ ] Known limitations acknowledged
- [ ] Code matches methods section of paper
- [ ] Version tagged in git
- [ ] Zenodo DOI obtained

---

## Critical Success Factors

1. **Reproducibility over elegance** - Working, documented code beats perfect architecture
2. **Transparency about limitations** - Acknowledge what doesn't work
3. **Minimal dependencies** - Fewer packages = easier to reproduce in 5 years
4. **Literate analysis** - R Markdown analysis/ files explain *why* not just *what*
5. **Version everything** - Code, packages, data versions all documented
6. **Test on clean machine** - You can't verify reproducibility from your dev machine

---

## References & Resources

- **Research Compendium:** https://research-compendium.science/
- **rOpenSci Packages Guide:** https://devguide.ropensci.org/ (even though not submitting, good standards)
- **TIER Protocol:** https://www.projecttier.org/ (social science reproducibility)
- **Reproducible Research in R:** https://bookdown.org/pdr_higgins/rmrwr/
- **renv documentation:** https://rstudio.github.io/renv/
- **Zenodo-GitHub integration:** https://docs.github.com/en/repositories/archiving-a-github-repository/referencing-and-citing-content

---

## Next Steps

1. Review this plan and adjust priorities based on paper timeline
2. Decide on Phase 4.3 (Docker) - worth the complexity?
3. Start with Phase 1.1 (code audit) to understand current state
4. Block out time for each phase based on urgency

**Estimated total effort:** 6-8 weeks of focused work, or ongoing alongside research over 3-4 months.
