---
created: 2025-08-27T21:35:45Z
last_updated: 2025-08-27T21:35:45Z
version: 1.0
author: Claude Code PM System
---

# Project Structure

## Root Directory Organization

```
IPV_detection_in_NVDRS/
├── .claude/               # Claude Code configuration and context
│   ├── context/          # Project context documentation
│   ├── scripts/          # PM and automation scripts
│   └── ...              # Other Claude configuration
├── data-raw/             # Raw data files
│   └── suicide_IPV_manuallyflagged.xlsx  # Test dataset with manual flags
├── docs/                 # Core implementation files
│   ├── ULTIMATE_CLEAN.R     # Primary 30-line implementation
│   ├── CLEAN_IMPLEMENTATION.R # Alternative 100-line version
│   └── *.md             # Documentation files
├── config/               # Configuration files (legacy)
├── logs/                 # API call logs and debugging
├── results/              # Output directory for analysis results
├── tests/                # Test files and validation scripts
├── R/                    # R scripts directory (currently empty)
├── README.md             # Project documentation
├── CLAUDE.md            # Claude Code specific instructions
├── CLAUDE.local.md      # Local Claude configuration
└── IPV_detection_in_NVDRS.Rproj  # RStudio project file
```

## Key Directories

### `/docs` - Core Implementation
- **Purpose**: Contains the actual working code
- **Key Files**: 
  - `ULTIMATE_CLEAN.R` - The entire IPV detection in 30 lines
  - `CLEAN_IMPLEMENTATION.R` - Extended version with batching support
- **Philosophy**: Code lives here, not in complex package structures

### `/data-raw` - Source Data
- **Purpose**: Store raw input data files
- **Format**: Excel files (.xlsx)
- **Content**: NVDRS narratives with manual IPV flags for validation

### `/logs` - Operational Logs
- **Purpose**: Track API calls and debugging information
- **Format**: SQLite database or text logs
- **Usage**: User-controlled logging for troubleshooting

### `/results` - Output Storage
- **Purpose**: Store analysis results and exports
- **Format**: CSV, JSON, or RDS files
- **Content**: IPV detection results from batch processing

### `/.claude` - Claude Code Integration
- **Purpose**: Configuration for Claude Code assistant
- **Content**: Context files, scripts, rules, and PM tools
- **Note**: Project-specific Claude customization

## File Naming Conventions

### R Scripts
- Implementation files: `ULTIMATE_*.R` for core, `CLEAN_*.R` for extended
- Test scripts: `test_*.R`
- Analysis scripts: `analyze_*.R`

### Data Files
- Input data: Descriptive names with underscores
- Results: Include timestamp or version in filename
- Documentation: UPPERCASE for importance (README, CLAUDE)

## Deprecated/Legacy Structure

The project previously had complex package structure that has been removed:
- ~~`/nvdrsipvdetector/`~~ - Removed R package directory
- ~~`/scripts/`~~ - Removed complex utility scripts
- ~~`/test/`~~ - Removed complex test harness

## Current Simplification

Following Unix philosophy, the project now consists of:
1. **One function** (`detect_ipv`) in one file
2. **User data** in data-raw/
3. **User results** in results/
4. **Minimal dependencies** (httr2, jsonlite)

No hidden directories, no complex hierarchies, no magic.