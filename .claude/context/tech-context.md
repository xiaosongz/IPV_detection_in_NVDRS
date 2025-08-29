---
created: 2025-08-27T21:35:45Z
last_updated: 2025-08-29T16:33:40Z
version: 1.2
author: Claude Code PM System
---

# Technology Context

## Primary Language
- **R** (Statistical Computing Language)
- **Version**: R 4.0+ recommended
- **IDE**: RStudio (optional, any text editor works)
- **Style Guide**: Tidyverse (enforced as of v0.2.0)

## Core Dependencies

### Required Packages
```r
# API and parsing
install.packages(c("httr2", "jsonlite"))

# Database storage
install.packages(c("DBI", "RSQLite", "RPostgres", "digest"))
```

1. **httr2** (>= 1.0.0) - HTTP client for API calls
   - Purpose: Send requests to LLM API
   - Usage: POST requests to chat completion endpoints

2. **jsonlite** (>= 1.8.0) - JSON parsing
   - Purpose: Parse LLM responses
   - Usage: Convert JSON strings to R objects

3. **DBI** - Database interface
   - Purpose: Abstract database operations
   - Usage: Connect to and query databases

4. **RSQLite** - SQLite driver
   - Purpose: SQLite database backend
   - Usage: Zero-configuration local storage

5. **RPostgres** - PostgreSQL driver
   - Purpose: PostgreSQL database backend  
   - Usage: Scalable, multi-user database

6. **digest** - Cryptographic hash functions
   - Purpose: Generate content hashes for prompt deduplication
   - Usage: SHA-256 hashing in experiment tracking

### Testing Packages
```r
# For comprehensive testing
install.packages("testthat")
```

### Optional Packages (User Choice)
```r
# For reading Excel test data
install.packages("readxl")

# For parallel processing (user's choice)
install.packages("parallel")

# For progress bars (if desired)
install.packages("progress")
```

## LLM Integration

### Primary LLM Provider
- **LM Studio** (Local LLM server)
- **Endpoint**: `http://192.168.10.22:1234/v1/chat/completions`
- **Protocol**: OpenAI-compatible API
- **Models Tested**:
  - `openai/gpt-oss-120b` (recommended)
  - `qwen/qwen3-30b-a3b-2507`

### Configuration Method
```r
# Environment variables
Sys.setenv(LLM_API_URL = "http://192.168.10.22:1234/v1/chat/completions")
Sys.setenv(LLM_MODEL = "openai/gpt-oss-120b")

# Or pass config directly
config <- list(
  api_url = "your-endpoint",
  model = "your-model"
)
```

## Development Tools

### Version Control
- **Git** - Source control
- **GitHub** - Repository hosting (xiaosongz/IPV_detection_in_NVDRS)
- **Branch Strategy**: Feature branches (currently on `dev_c`)

### Project Management
- **RStudio Project** (.Rproj file for IDE integration)
- **Claude Code** - AI pair programming assistant
- **.claude/** - Claude-specific configuration

## Data Formats

### Input
- **Excel** (.xlsx) - Primary data format
- **CSV** - Alternative format (user can convert)
- **Text** - Raw narrative strings

### Output
- **List** - R native data structure
- **JSON** - API response format
- **CSV** - Export format (user controlled)

## System Requirements

### Minimal Requirements
- R installation
- Internet connection (for LLM API)
- 2 R packages (httr2, jsonlite)

### No Requirements For
- ❌ Complex R package installation
- ❌ Database systems
- ❌ Web servers
- ❌ Docker/containers
- ❌ Special IDE or tools

## Architecture Decisions

### What We Use
- **Functional Programming** - Pure functions, no side effects
- **Environment Variables** - Configuration management
- **Standard R** - Base R operations, no tidyverse required
- **Simple Data Structures** - Lists and data frames only

### What We Don't Use
- ❌ Object-oriented programming (no R6, S4, Reference Classes)
- ❌ Complex package structures
- ❌ Dependency injection
- ❌ Abstract interfaces
- ❌ Framework-specific patterns

## Performance Characteristics

### API Performance
- **Latency**: ~500-2000ms per request (LM Studio)
- **Throughput**: ~2-5 requests/second
- **Token Limits**: Model-dependent (typically 4K-32K)

### Processing Capabilities
- **Single-threaded**: Default, simple
- **Parallel**: User can implement with `parallel::mclapply`
- **Batch Size**: User-controlled, no framework limits

## Security Considerations

### API Security
- No API keys in code
- Environment variables for sensitive data
- Local LLM option for data privacy

### Data Privacy
- Local processing option with LM Studio
- No cloud dependencies required
- User controls all data flow