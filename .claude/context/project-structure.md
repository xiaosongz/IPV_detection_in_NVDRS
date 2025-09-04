---
created: 2025-08-27T21:35:45Z
last_updated: 2025-09-02T19:44:32Z
version: 1.9
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
├── benchmark_results/    # Benchmark output files (NEW)
│   └── benchmark_results_*.{csv,json}  # Timestamped results
├── data-raw/             # Raw data files
│   └── suicide_IPV_manuallyflagged.xlsx  # Test dataset with manual flags
├── docs/                 # Core implementation files
│   ├── ULTIMATE_CLEAN.R     # Primary minimal implementation
│   ├── CLEAN_IMPLEMENTATION.R # Extended version with batching
│   ├── LLM_RESPONSE_ANALYSIS.md # Analysis of LLM response structures
│   ├── PROMPT_STRUCTURE_ANALYSIS.md # Prompt engineering documentation
│   ├── EXPERIMENT_MODE_GUIDE.md # Complete guide for R&D experiment tracking
│   ├── PERFORMANCE_CHARACTERISTICS.md # System performance metrics
│   ├── PRODUCTION_VALIDATION.md # Production readiness certification
│   ├── POSTGRESQL_SETUP.md # PostgreSQL configuration guide
│   ├── SQLITE_SETUP.md  # SQLite setup and optimization guide
│   ├── TROUBLESHOOTING.md # Comprehensive troubleshooting guide
│   └── *.md             # Documentation files
├── examples/             # Usage examples
│   ├── parser_example.R # Example of parsing LLM responses
│   ├── database_setup_example.R # Database connection and setup
│   ├── batch_processing_example.R # Efficient batch processing
│   ├── experiment_tracking_example.R # Research and experimentation
│   └── integration_example.R # Complete end-to-end workflow (updated for benchmark_results/)
├── config/               # Configuration templates
│   ├── .env.example      # Environment variables template
│   └── config.yml.example # Configuration YAML template
├── logs/                 # API call logs and debugging
├── results/              # Output directory for analysis results
├── tests/                # Test files and validation scripts
│   ├── testthat/         # Streamlined unit tests (6 focused test files)
│   │   ├── test-build_prompt.R      # Prompt building functionality
│   │   ├── test-call_llm.R          # LLM API interface testing  
│   │   ├── test-parse_llm_result.R  # Response parsing validation
│   │   ├── test-db_utils.R          # Database connectivity (SQLite/PostgreSQL)
│   │   ├── test-store_llm_result.R  # Result storage testing
│   │   └── test-detect_ipv.R        # Core IPV detection logic
│   ├── integration/      # Integration test suite (Issue #6)
│   │   ├── helpers/      # Test data and mock helpers
│   │   ├── test_full_workflow.R     # End-to-end workflow testing
│   │   ├── test_error_scenarios.R   # Error handling validation
│   │   ├── test_database_backends.R # SQLite/PostgreSQL comparison
│   │   ├── test_concurrent_access.R # Concurrent access testing
│   │   ├── test_production_scenarios.R # Production readiness
│   │   ├── run_integration_tests.R  # Test runner with reporting
│   │   └── README.md     # Integration test documentation
│   ├── performance/      # Performance benchmarks
│   │   ├── benchmark_postgres.R     # PostgreSQL performance testing
│   │   ├── integration_benchmarks.R # Component benchmarking
│   │   ├── load_testing.R          # High-volume load testing
│   │   ├── memory_profiling.R      # Memory leak detection
│   │   └── validate_performance_targets.R  # Performance validation
│   ├── PERFORMANCE_REALITY_CHECK.md # Honest performance documentation
│   └── *.R              # Test utility scripts
├── R/                    # Core R functions (modular)
│   ├── 0_setup.R         # Direct execution setup script
│   ├── build_prompt.R    # Message formatting function
│   ├── call_llm.R       # LLM API interface function
│   ├── call_llm_batch.R  # EXPERIMENTAL batch processing functions (untested)
│   ├── parse_llm_result.R # Parse LLM responses to structured data
│   ├── db_utils.R       # Database connection utilities (SQLite & PostgreSQL)
│   ├── store_llm_result.R # Store parsed results in database
│   ├── experiment_utils.R # Prompt versioning and experiment management
│   ├── experiment_analysis.R # Statistical comparison and A/B testing
│   ├── utils.R          # Utility functions (trimws_safe, null_or_empty operator)
│   └── IPVdetection-package.R # Package metadata
├── inst/                 # Package installed files
│   └── sql/             # SQL schema and migrations
│       ├── schema.sql   # Basic database schema (SQLite/PostgreSQL compatible)
│       └── experiment_schema.sql # R&D experiment tracking schema
├── scripts/              # Benchmark and utility scripts
│   ├── run_benchmark.R  # Standard benchmark script (updated for benchmark_results/)
│   ├── run_benchmark_optimized.R # EXPERIMENTAL optimized benchmark (untested)
│   └── migrate_sqlite_to_postgres.R # SQLite to PostgreSQL migration tool
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
  - `ULTIMATE_CLEAN.R` - Original minimal implementation
  - `CLEAN_IMPLEMENTATION.R` - Extended version with batching support
- **Philosophy**: Historical reference, actual code now in `/R`

### `/data-raw` - Source Data
- **Purpose**: Store raw input data files
- **Format**: Excel files (.xlsx)
- **Content**: NVDRS narratives with manual IPV flags for validation

### `/logs` - Operational Logs
- **Purpose**: Track API calls and debugging information
- **Format**: Database (SQLite/PostgreSQL) or text logs
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
- 2025-08-29 (19:33): Added comprehensive integration and performance test suites from Issue #6
- 2025-08-29: Test suite cleaned and optimized - removed 2 outdated files, streamlined 6 core test files
- 2025-08-29: Performance benchmarks directory updated with PostgreSQL-specific testing tools
- 2025-08-28: Added R package structure with modular functions, comprehensive testing framework, and JSON-based configuration while maintaining Unix philosophy