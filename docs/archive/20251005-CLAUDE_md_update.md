# CLAUDE.md Update Summary

**Date:** 2025-10-05

## Changes Made

Updated `/Volumes/DATA/git/IPV_detection_in_NVDRS/CLAUDE.md` to accurately reflect current project status as a **research compendium** rather than a traditional R package.

### Key Updates

#### 1. Project Type Clarification (NEW SECTION)
- **Added:** Explicit statement that this is a research compendium, not a loadable R package
- **Added:** Current stage (testing with 404 narratives, planning 60k production run)
- **Added:** Publication goal (peer-reviewed paper with repo as supplementary materials)

#### 2. Architecture Section
- **Changed:** "Three Layers" → "Two Layers" (removed reference to non-existent `docs/ULTIMATE_CLEAN.R`)
- **Changed:** "Production package" → "Modular functions" (more accurate terminology)
- **Changed:** "Package provides minimal building blocks" → "R functions are minimal building blocks"

#### 3. Common Commands
- **Removed:** Misleading "R Package Development" section with `devtools::load_all()` and `devtools::check()`
- **Replaced with:** "Documentation" section noting that functions are accessed via `source()`, not `library()`
- **Clarified:** Roxygen docs kept for reference and potential future package conversion

#### 4. File Organization
- **Added:** File naming convention section
  - Documentation files: `YYYYMMDD-description.md`
  - Analysis reports: `YYYYMMDD-report_name.Rmd/html`
  - Experiment configs: `exp_NNN_description.yaml`
- **Updated:** Directory descriptions to reflect actual usage
- **Removed:** Reference to non-existent `docs/ULTIMATE_CLEAN.R`
- **Added:** `docs/analysis/` directory
- **Corrected:** Test count (207 tests)

#### 5. Development Rules
- **Added:** NO INCONSISTENT NAMING rule (was in `.claude/CLAUDE.md` but missing from main)

#### 6. Agent Usage
- **Added:** Principle "Think carefully and implement the most concise solution that changes as little code as possible"
- **Enhanced:** Descriptions for file-analyzer, code-analyzer, and test-runner agents
- **Clarified:** Benefits of using agents (context optimization, no approval dialogs)

#### 7. Tone Section
- **Updated:** Language to match `.claude/CLAUDE.md` version more closely
- **Added:** "Tell me if there's a relevant standard or convention I'm unaware of"

#### 8. Publication Readiness (NEW SECTION)
- **Added:** Reference to `docs/20251005-publication_readiness_plan.md`

## Why These Changes Matter

### Before:
- File described project as an R package with `devtools::load_all()` workflow
- Suggested running `devtools::check()` for package validation
- Referenced non-existent files
- Mixed package terminology with actual research compendium usage

### After:
- Accurately describes project as research compendium
- Explains actual usage pattern (`source()` not `library()`)
- Documents file naming conventions
- Clarifies publication goals
- Aligns with actual development practices

## Files Modified

1. `/Volumes/DATA/git/IPV_detection_in_NVDRS/CLAUDE.md` - Main project documentation for Claude Code

## Related Documentation

- `/Volumes/DATA/git/IPV_detection_in_NVDRS/.claude/CLAUDE.md` - Concise agent instructions (unchanged)
- `/Volumes/DATA/git/IPV_detection_in_NVDRS/docs/20251005-publication_readiness_plan.md` - Publication preparation plan

## Impact

- Claude Code will now correctly understand this is a research compendium, not a package
- No more suggestions to use `library()` or package development tools
- Proper understanding of file naming conventions
- Awareness of publication goals and reproducibility focus
