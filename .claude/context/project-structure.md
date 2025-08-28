---
created: 2025-08-27T21:35:45Z
last_updated: 2025-08-28T13:33:43Z
version: 1.2
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
│   ├── LLM_RESPONSE_ANALYSIS.md # Analysis of LLM response structures
│   ├── PROMPT_STRUCTURE_ANALYSIS.md # Prompt engineering documentation
│   └── *.md             # Documentation files
├── examples/             # Usage examples
│   └── parser_example.R # Example of parsing LLM responses
├── config/               # Configuration files (legacy)
├── logs/                 # API call logs and debugging
├── results/              # Output directory for analysis results
├── tests/                # Test files and validation scripts
│   ├── testthat/         # Comprehensive unit tests
│   │   ├── test-build_prompt.R
│   │   ├── test-call_llm.R
│   │   ├── test-parse_llm_result.R
│   │   ├── test-db_utils.R
│   │   └── test-store_llm_result.R
│   ├── performance/      # Performance benchmarks
│   │   └── benchmark_storage.R
│   ├── test_prompt.json  # Structured test prompts
│   └── *.R              # Test utility scripts
├── R/                    # Core R functions (modular)
│   ├── 0_setup.R         # Direct execution setup script
│   ├── build_prompt.R    # Message formatting function
│   ├── call_llm.R       # LLM API interface function
│   ├── parse_llm_result.R # Parse LLM responses to structured data
│   ├── db_utils.R       # SQLite database connection utilities
│   ├── store_llm_result.R # Store parsed results in database
│   └── IPVdetection-package.R # Package metadata
├── inst/                 # Package installed files
│   └── sql/             # SQL schema and migrations
│       └── schema.sql   # SQLite database schema
├── README.md             # Project documentation
├── CLAUDE.md            # Claude Code specific instructions
├── CLAUDE.local.md      # Local Claude configuration
└── IPV_detection_in_NVDRS.Rproj  # RStudio project file
```

## Key Directories

### `/R` - Core Implementation
- **Purpose**: Contains the modular R functions following package structure
- **Key Files**: 
  - `call_llm.R` - Main LLM interface function (requires both prompts)
  - `build_prompt.R` - Message formatting utility
  - `0_setup.R` - Direct execution setup script
- **Philosophy**: One function per file, clear separation of concerns

### `/docs` - Legacy Implementation & Documentation  
- **Purpose**: Contains reference implementations and documentation
- **Key Files**: 
  - `ULTIMATE_CLEAN.R` - Original 30-line implementation
  - `CLEAN_IMPLEMENTATION.R` - Extended version with batching support
- **Philosophy**: Historical reference, actual code now in `/R`

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

## Current Architecture

Following Unix philosophy with modular design, the project now consists of:
1. **Two focused functions** (`build_prompt`, `call_llm`) with clear separation
2. **Comprehensive testing** (77+ test cases in testthat/)  
3. **Direct setup** (0_setup.R executes on source)
4. **User data** in data-raw/
5. **User results** in results/
6. **Minimal dependencies** (httr2, jsonlite)

Clean package structure without complex hierarchies or magic.

## Update History
- 2025-08-28: Added R package structure with modular functions, comprehensive testing framework, and JSON-based configuration while maintaining Unix philosophy