# 20251005-Publication Readiness Task List

**Project Type:** Research Compendium - Not a loadable R package. Scripts use `source()` to load functions from `R/`. Focus is reproducibility for publication, not distribution. Will be published as supplementary materials to peer-reviewed paper.

**Status Guide:**
- ✅ Completed
- 🔄 In Progress  
- ⏳ Not Started
- 🎯 Critical Path (must complete before submission)
- 📊 High Impact
- 📝 Documentation Focus

---

## Phase 1: Foundation & Scope (Week 1)

### 1.1 Code Audit & Organization
- ✅ Audit current codebase and categorize functions **[COMPLETED - 12 active + 8 legacy files]**
- ✅ Remove all dead code to legacy directory **[COMPLETED]**
- ✅ Fix test suite hanging issues **[COMPLETED - 207 tests working]**
- ✅ Create `docs/code_inventory.md` documenting function categorization **[COMPLETED]**

### 1.2 Repository Structure
- ✅ Define research compendium structure **[MOSTLY DONE - structure exists]**
- ✅ Create `docs/compendium_structure.md` explaining each directory's role **[COMPLETED]**
- ✅ Document the two-layer architecture (Modular functions + Experiment orchestration) **[COMPLETED]**

### 1.3 Immediate Critical Tasks 🎯
- ✅ Create synthetic example data for reviewer testing **[COMPLETED]**
- ✅ Set up dependency management with renv **[COMPLETED]**
- ✅ Create `.env.example` with environment variable templates **[COMPLETED]**

---

## Phase 2: Core Documentation (Week 1-2)

### 2.1 README.md (Critical for Reviewers) 🎯📊
- ⏳ Write comprehensive README.md with:
  - 📝 Purpose and research question
  - 📝 Citation information (placeholder)
  - 📝 System requirements (R version, packages)
  - 📝 Installation instructions
  - 📝 Data access instructions for NVDRS
  - 📝 Reproducible workflow steps
  - 📝 Repository structure overview
  - 📝 License and ethical considerations

### 2.2 Script Documentation 📊
- ✅ Add comprehensive header comments to `scripts/run_experiment.R` **[PARTIALLY DONE]**
- ⏳ Document all scripts in `scripts/` directory
- 📝 Create `scripts/README.md` documenting workflow sequence
- 📝 Add usage examples and runtime expectations

### 2.3 Function Documentation
- ✅ Update roxygen comments for all active functions **[MOSTLY DONE]**
- ⏳ Regenerate .Rd files with `devtools::document()` (optional - for completeness)
- 📝 Add runnable examples (use `\dontrun{}` for API calls)
- 📝 Ensure all functions have complete docs (accessed via source(), not library())

---

## Phase 3: Reproducible Analysis (Week 2)

### 3.1 Synthetic Example Data 🎯📊
- ⏳ Generate realistic fake suicide narratives (100-200 examples)
- ⏳ Include positive/negative IPV cases
- ⏳ Save as `data/synthetic_narratives.csv`
- 📝 Document generation process
- 📝 Add disclaimer in README about synthetic nature

### 3.2 Demo Workflow 🎯📊
- ⏳ Create `scripts/demo_workflow.R` that:
  - Uses synthetic data
  - Runs detection on small sample
  - Stores results in SQLite
  - Generates basic metrics
  - Completes in <5 minutes
- 📝 Document demo script purpose and usage

### 3.3 Analysis Notebooks 📊
- ⏳ Create `analysis/20251005-experiment_comparison.Rmd` - Compare prompt/model performance
- ⏳ Create `analysis/20251005-error_analysis.Rmd` - Analyze failure modes
- ⏳ Create `analysis/20251005-reproduce_paper_figures.Rmd` - Generate all paper figures/tables
- ⏳ Create `analysis/20251005-validation_metrics.Rmd` - Compute accuracy metrics

---

## Phase 4: Computational Environment (Week 2-3)

### 4.1 Dependency Management 🎯
- ⏳ Initialize renv: `renv::init()`
- ⏳ Create snapshot: `renv::snapshot()`
- 📝 Commit `renv.lock` to git
- 📝 Document renv usage in README

### 4.2 Environment Setup 🎯
- ⏳ Create `.env.example` with all required variables:
  - 📝 OPENAI_API_KEY documentation
  - 📝 ANTHROPIC_API_KEY documentation  
  - 📝 PG_CONN_STR documentation
- 📝 Add setup instructions to README
- ✅ Ensure real `.env` never committed to git **[ALREADY HANDLED]**

### 4.3 Docker Container (Optional - Defer) 📝
- ⏳ Create `Dockerfile` (consider deferring for timeline)
- ⏳ Document docker-compose workflow
- 📝 Document decision to skip or include with rationale for research compendium

---

## Phase 5: Data & Schema Documentation (Week 3)

### 5.1 Database Schema 📊
- ⏳ Create `docs/database_schema.md`
- 📝 Document experiments table structure
- 📝 Document narratives table structure
- 📝 Document schema migrations
- 📝 Document SQLite → PostgreSQL sync process

### 5.2 Data Provenance 📊
- ⏳ Create `docs/data_provenance.md`
- 📝 Document NVDRS data source and access process
- 📝 Document date range of narratives used
- 📝 Document inclusion/exclusion criteria
- 📝 Document gold-standard labeling process
- 📝 Include IRB approval number

### 5.3 Results Structure 📝
- ⏳ Create `docs/20251005-results_structure.md`
- 📝 Document where experiments write results
- 📝 Document file naming conventions (including YYYYMMDD- prefix)
- 📝 Document how to interpret logs
- 📝 Document archival process for supplementary materials

---

## Phase 6: Testing & Validation (Week 3)

### 6.1 Test Suite Documentation 📊
- ⏳ Create `tests/README.md`
- 📝 Document how to run tests for research compendium
- 📝 Document test coverage (if available)
- 📝 Document what's tested vs. what's not tested
- 📝 Document integration test process using source() loaded functions

### 6.2 Validation Benchmark 📊
- ⏳ Create `scripts/validate_against_gold_standard.R` (if applicable)
- ⏳ Compute precision, recall, F1 against gold standard
- 📝 Document in `docs/20251005-validation_results.md`
- 📝 Make reproducible with synthetic data

### 6.3 Limitations Documentation 📊
- ⏳ Create `docs/20251005-limitations.md`
- 📝 Document model hallucination cases
- 📝 Document edge cases that fail
- 📝 Document computational cost constraints for 60k production run
- 📝 Document generalizability concerns for supplementary material

---

## Phase 7: Publication Metadata (Week 4)

### 7.1 Citation Files 📊
- ⏳ Create `inst/CITATION` file with R citation format
- ⏳ Create `CITATION.cff` for GitHub standard
- 📝 Update when paper is published
- 📝 Document that this is supplementary material to peer-reviewed paper

### 7.2 DESCRIPTION Cleanup 📊
- ⏳ Update title and description
- ⏳ Add all authors with proper roles (aut, cre, ctb)
- ⏳ Add all dependencies with minimum versions
- ⏳ Remove unused dependencies
- ⏳ Add license field

### 7.3 Versioning & Changelog 📊
- ⏳ Start at version 0.1.0 (pre-publication)
- ⏳ Create `NEWS.md` tracking changes
- 📝 Document versioning approach for supplementary material
- ⏳ Tag git release: `git tag v0.1.0`

### 7.4 License 📊
- ⏳ Choose appropriate license (GPL-3 or MIT for research)
- ⏳ Add `LICENSE` file
- ⏳ Add license headers in key files

---

## Phase 8: Distribution & Archival (Week 4)

### 8.1 GitHub Repository Polish 📊
- ⏳ Verify README renders correctly on GitHub
- ✅ Ensure good .gitignore **[ALREADY DONE]**
- ⏳ Add repository topics/tags for discoverability
- ⏳ Fill in repository description
- ⏳ Add link to paper when available
- ⏳ Consider adding CONTRIBUTING.md (optional)

### 8.2 Zenodo DOI (Post-Publication Priority)
- ⏳ Link GitHub repo to Zenodo
- ⏳ Create release: `git tag v1.0.0 && git push --tags`
- ⏳ Add DOI badge to README
- 📝 Document DOI in paper

### 8.3 Supplementary Materials
- ⏳ Create `supplementary_materials/` directory
- ⏳ Include README, key scripts, synthetic data, analysis notebooks
- ⏳ Package as .zip for submission to journal
- 📝 Document relationship to GitHub repo and paper

### 8.4 Installation Testing 🎯
- ⏳ Test on clean machine or VM:
  - Clone repository fresh
  - Follow README installation instructions
  - Run demo_workflow.R
  - Verify everything works
- 📝 Document any issues found

---

## Phase 9: Paper Alignment (Ongoing)

### 9.1 Methods Section Consistency
- ⏳ Ensure algorithm descriptions match implementation
- ⏳ Document hyperparameters (temperature, max_tokens, etc.)
- ⏳ Ensure prompt versions correspond to experiments
- ⏳ Verify metrics definitions match computation
- 📝 Create code-paper alignment checklist

### 9.2 Figures & Tables Reproducibility 📊
- ⏳ Ensure every figure/table has corresponding script in `analysis/` (with YYYYMMDD- prefix)
- ⏳ Verify all use committed configs/data
- ⏳ Make reproducible from command line
- ⏳ Create `analysis/20251005-reproduce_paper.sh` that generates everything

### 9.3 Reviewer Response Preparation
- 📝 Document how to add new models
- 📝 Document how to add new prompts
- 📝 Prepare error analysis examples
- 📝 Document computational costs

---

## Priority Timeline

### Must-Have (Before Submission) 🎯
- **Week 1**: Phase 1.3, 2.1 (README), 4.1 (renv), 4.2 (.env)
- **Week 2**: Phase 3.1 (synthetic data), 3.2 (demo), 3.3 (analysis notebooks)
- **Week 3**: Phase 5.1 (schema), 5.2 (provenance), 6.3 (limitations)
- **Week 4**: Phase 7 (metadata), 8.1 (GitHub), 8.4 (testing), 9 (alignment)

### Should-Have (Before Publication) 📊
- Phase 2.2-2.3 (documentation completion)
- Phase 4.3 (Docker, if time permits)
- Phase 6.1-6.2 (testing docs, validation)
- Phase 8.2 (Zenodo DOI)

### Nice-to-Have (Post-Publication)
- pkgdown website
- Video walkthrough
- Extended documentation
- Additional validation studies

---

## Quick Win Tasks (Start Here)

1. **Create `.env.example`** - 30 minutes, critical for setup
2. **Initialize renv** - 15 minutes, locks dependencies
3. **Write basic README structure** - 2 hours, enables reviewer access
4. **Generate synthetic data** - 4 hours, biggest blocker for reviewers
5. **Create demo script** - 2 hours, proves system works
6. **Update all new documentation with YYYYMMDD- prefix** - 15 minutes, follows project convention

---

## Quality Checklist

Before considering "publication ready," verify:

- [ ] Reviewer can clone repo and run demo without contacting authors
- [ ] All paper figures/tables have reproducible source
- [ ] Dependencies explicitly versioned with renv
- [ ] No hardcoded paths or credentials in code
- [ ] Synthetic data allows testing without NVDRS access
- [ ] README installation instructions tested on clean machine
- [ ] All functions used in paper have documentation (accessed via source())
- [ ] Database schema matches what code expects
- [ ] License permits intended use as supplementary material
- [ ] Citation information complete (including paper reference)
- [ ] Ethical considerations documented
- [ ] Known limitations acknowledged
- [ ] Code matches methods section of paper
- [ ] Version tagged in git
- [ ] GitHub repository polished for reviewer access

---

## Weekly Sprint Goals

### Week 1 Sprint Goal: Reviewer Accessibility
- Synthetic data created
- Demo script working
- Basic README with installation instructions for research compendium
- Environment setup documented
- All new documentation follows YYYYMMDD- prefix convention

### Week 2 Sprint Goal: Analysis Reproducibility
- All analysis notebooks created
- Paper figures reproducible
- Schema and provenance documented

### Week 3 Sprint Goal: Publication Polish
- Complete documentation
- License and metadata
- GitHub repository ready

### Week 4 Sprint Goal: Final Validation
- Clean machine testing
- Code-paper alignment
- Ready for submission

---

**Total Estimated Effort**: 4-5 focused weeks (reduced from 8 weeks based on current repository state)

**Key Success Factor**: Focus on reviewer accessibility first (synthetic data + demo), then comprehensive documentation.