# Standalone IPV Detection Analysis

This directory contains a self-contained R Markdown analysis file for examining IPV (Intimate Partner Violence) detection experiments from the NVDRS suicide narratives project. The report focuses on clean, publication‑quality tables and plots with minimal console output.

## Files

- `20251006-standalone_experiment_analysis.Rmd` - Complete standalone analysis
- `README.md` - This file

## Requirements

To run the analysis you need:

1. The R Markdown file: `20251006-standalone_experiment_analysis.Rmd`
2. The SQLite database: `data/experiments.db` (resolved via `here::here()`)
3. Required R packages pre‑installed: `DBI`, `RSQLite`, `dplyr`, `ggplot2`, `knitr`, `kableExtra`, `tidyr`, `purrr`, `scales`, `readr`, `DT`, `htmltools`, `here`

All helper functions are embedded in the Rmd; no other project files are required.

## Setup Instructions

1. **Create the directory structure (project root):**
   ```
   project_root/
   ├── standalone_analysis/
   │   └── 20251006-standalone_experiment_analysis.Rmd
   └── data/
       └── experiments.db
   ```

2. **Install R packages (if not already installed):**
   The Rmd does not auto‑install packages. Install them once:
   ```r
   install.packages(c(
     "DBI", "RSQLite", "dplyr", "ggplot2", "knitr",
     "kableExtra", "tidyr", "purrr", "scales", "readr", "DT"
   ))
   ```

3. **Run the analysis:**
   - Open the project root in RStudio and knit `standalone_analysis/20251006-standalone_experiment_analysis.Rmd`
   - OR run: `rmarkdown::render("standalone_analysis/20251006-standalone_experiment_analysis.Rmd")`
   
   Paths use the `here` package for robustness. If `here` cannot infer the root, set it once per session:
   ```r
   here::i_am("standalone_analysis/20251006-standalone_experiment_analysis.Rmd")
   ```

## What the Analysis Covers

### Database Overview
- Table structure verification
- Record counts and status summaries

### Performance Analysis
- **Model Comparison**: F1 scores across different LLMs with faceted plots
- **Model-Specific Deep Dives**: Individual analysis for each model including:
  - Temperature impact with error bars
  - Prompt version effectiveness comparison
  - Configuration heatmaps showing optimal settings
- **Cross-Model Comparisons**: Side-by-side faceted visualizations
- **Runtime Efficiency**: Processing speed analysis by model
- **Interactive Data Tables**: DT tables for filtering and sorting detailed results

### Statistical Analysis
- Performance distributions and histograms
- Precision vs Recall tradeoffs
- Statistical summaries and confidence intervals

### Visualizations
- **NEW: Model-Specific Visualizations**: Clear, focused analysis per model
- **Faceted Plots**: Easy comparison across models without clutter
- **Error Bars**: Statistical significance shown on all comparisons
- **Configuration Heatmaps**: Optimal temperature/prompt combinations
- **Publication-Quality**: Consistent theming throughout
- **Interactive Tables**: DT tables with filtering, sorting, and search
- **Clean Output**: No verbose text; professional tables and plots

### Export Capabilities
- CSV exports of key metrics
- Performance summaries for further analysis
- Exports saved under `results/standalone_analysis/`

## Key Features

✅ **Completely Standalone**: No external R files needed  
✅ **Clear Errors**: Fails fast if DB/packages missing  
✅ **Publication Ready**: Professional formatting and plots  
✅ **Reproducible**: All code included and documented  
✅ **Customizable**: Easy to modify for specific needs  

## Database Schema Compatibility

This analysis works with SQLite databases containing these tables:

### `experiments` table
- experiment_id, experiment_name, status
- model_name, temperature, prompt_version  
- Performance metrics (f1_ipv, precision_ipv, recall_ipv)
- Runtime information, timestamps

### `narrative_results` table
- experiment_id, incident_id, narrative_type
- Detection results (detected, confidence, indicators)
- Manual flags and classification outcomes
- Error information and token usage

## Customization Tips

### Filter Experiments
```r
# In the setup chunk, modify the filter:
completed_exps <- experiments %>%
  filter(status == "completed", 
         model_name == "gpt-4",  # Add model filter
         !is.na(f1_ipv))
```

### Change Performance Metrics
```r
# Focus on precision instead of F1
arrange(desc(precision_ipv))
```

### Add New Visualizations
```r
# Add custom plots in any chunk
ggplot(completed_exps, aes(x = temperature, y = f1_ipv)) +
  geom_point() + 
  theme_minimal()
```

## Troubleshooting

**"Database file not found" error:**
- Ensure `data/experiments.db` exists in the correct location
- Check that the path is relative to the R Markdown file

**Package issues:**
- Ensure required packages are installed (see Setup)
- Restart R session if libraries fail to load

**Memory issues with large databases:**
- The analysis loads data efficiently, but very large databases may need filtering
- Add `LIMIT` clauses to SQL queries if needed

## Sharing with Colleagues

**To share this analysis:**

1. Send them this entire folder
2. Make sure they have R and RStudio installed  
3. They can run it immediately - no setup required!

**Alternative sharing:**
- Knit to HTML and share the HTML
- Export CSV results for Excel analysis
- Share individual plots as images

## Technical Notes

- Uses SQLite for maximum compatibility
- All functions are embedded – no `source()` calls
- Automatic database connection management
- Publication-ready plotting theme (Bootswatch flatly)
- Two‑decimal numeric formatting for readable tables
- Top‑10 table includes Accuracy alongside F1/Precision/Recall
- **Visualization Strategy**:
  - Separate panels for each model prevent visual clutter
  - Consistent color scheme and formatting
  - Statistical significance indicators (error bars)
  - Multiple visualization types for comprehensive analysis
  - **Interactive DT Tables**: Searchable, sortable displays
  - **Clean Inline Text**: Inline R and proper headers; no verbose console text

### Formatting and Spacing
- Headings render via Markdown with proper blank lines before/after
- Blank lines separate plots and tables for visual clarity
- Percentages displayed with two decimals; numeric values rounded to two decimals

## Support

This analysis is designed to be self-documenting. Each code chunk includes comments explaining the analysis steps. 

### Visualization Strategy
The updated analysis uses a **model-specific approach** instead of mixed visualizations:
- Each model gets its own analysis section with dedicated plots
- Temperature and prompt effects are analyzed separately for clarity
- Faceted plots enable easy cross-model comparison
- Configuration heatmaps reveal optimal settings per model

For questions about the underlying data structure or experimental methodology, refer to the main project documentation.
