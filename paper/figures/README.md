# Paper Figures

This directory contains publication-quality figures for the IPV detection methods paper.

## Generated Figures

### Figure 1: Incident Completeness (`fig_incident_completeness.*`)
- **Description**: Bar chart showing the distribution of narrative types in the dataset
- **Data**: 19,549 CME narratives and 15,763 LE narratives analyzed
- **Format**: PNG (300 DPI) and PDF

### Figure 2: Detection Rates by Narrative Type (`fig_detection_rates.*`)
- **Description**: Bar chart comparing IPV detection rates between CME and LE narratives
- **Key Findings**: 
  - CME detection rate: 5.6%
  - LE detection rate: 5.8%
- **Format**: PNG (300 DPI) and PDF

### Figure 3: Detection Agreement (`fig_agreement.*`)
- **Description**: Overall detection outcomes across all narratives
- **Format**: PNG (300 DPI) and PDF

### Figure 4: Confidence by Detection Outcome (`fig_confidence.*`)
- **Description**: Box plot showing model confidence scores for different detection outcomes
- **Key Findings**:
  - IPV Detected: Mean 0.865, Median 0.88
  - No IPV: Mean 0.896, Median 0.90
- **Format**: PNG (300 DPI) and PDF

## Data Source

- **Database**: `/Volumes/DATA/git/IPV_detection_in_NVDRS/data/production_20k.db`
- **Experiment ID**: `56841151-2bee-46dd-91c7-e230618b1c58`
- **Total Narratives**: 35,312

## Generation

All figures were generated using the script `paper/create_paper_figures.R` on 2025-12-16.
The script uses base R graphics to ensure compatibility and reproducibility.

## Usage

- **PNG files**: High resolution (300 DPI) suitable for digital publications and presentations
- **PDF files**: Vector format suitable for print publications and further editing
