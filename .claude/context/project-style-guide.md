---
created: 2025-08-27T21:35:45Z
last_updated: 2025-08-27T21:35:45Z
version: 1.0
author: Claude Code PM System
---

# Project Style Guide

USE Tidyverse style guide! 

## Core Principle
**"Good taste"** - Code that eliminates special cases and unnecessary complexity.

## R Code Style

### Function Design
```r
# GOOD - Single purpose, clear return
detect_ipv <- function(text, config = NULL) {
  # validate
  # process
  # return
}

# BAD - Multiple responsibilities
process_and_save_ipv <- function(text, output_file, log = TRUE) {
  # Too much happening
}
```

### Naming Conventions
- **Functions**: `verb_noun()` - lowercase with underscores
  - ✅ `detect_ipv()`, `load_config()`
  - ❌ `detectIPV()`, `LoadConfig()`

- **Variables**: Descriptive, lowercase
  - ✅ `narrative`, `api_url`, `confidence`
  - ❌ `n`, `URL`, `conf_score`

- **Files**: Descriptive with underscores
  - ✅ `ULTIMATE_CLEAN.R`, `test_data.csv`
  - ❌ `ultimateclean.R`, `TestData.csv`

### Code Structure
```r
# 1. Parameters with defaults
function_name <- function(required_param, optional = NULL) {
  
  # 2. Input validation (fail fast)
  if (is.null(required_param)) return(NULL)
  
  # 3. Main logic (no special cases)
  result <- process(required_param)
  
  # 4. Simple return
  result
}
```

### Error Handling
```r
# GOOD - Return predictable structure
tryCatch({
  # operation
}, error = function(e) {
  list(detected = NA, confidence = 0, error = e$message)
})

# BAD - Inconsistent returns
if (error) return(NULL)
if (other_error) return("Error")
if (another_error) stop("Fatal")
```

## Documentation Style

### Comments
```r
# Minimal comments - code should be self-documenting
# Only explain "why", not "what"

# BAD - Obvious comment
# Add 1 to x
x <- x + 1

# GOOD - Explains reasoning
# Token limit workaround for long narratives
if (nchar(text) > 4000) text <- substr(text, 1, 4000)
```

### README Structure
1. **What it is** (one line)
2. **The implementation** (show the code)
3. **How to use** (minimal examples)
4. **Why this way** (philosophy)

### No Documentation For
- ❌ Complex API references
- ❌ Detailed parameter descriptions  
- ❌ Extensive tutorials
- ❌ Architecture diagrams

## Configuration Style

### Environment Variables
```r
# GOOD - Clear defaults
Sys.getenv("LLM_API_URL", "http://localhost:1234/v1/chat/completions")

# BAD - No defaults or unclear names
Sys.getenv("URL")
```

### Config Objects
```r
# GOOD - Simple list
config <- list(
  api_url = "...",
  model = "..."
)

# BAD - Complex nested structures
config <- list(
  api = list(
    endpoints = list(
      chat = list(url = "...")
    )
  )
)
```

## Testing Style

### Testing with testthat
```r
# Use testthat for comprehensive testing
test_that("detect_ipv returns expected structure", {
  result <- detect_ipv("test narrative")
  expect_type(result, "list")
  expect_true("detected" %in% names(result))
  expect_true("confidence" %in% names(result))
})
```

### Testing Best Practices
- ✅ Use testthat for unit tests
- ✅ Write meaningful tests that catch real bugs
- ✅ Test edge cases and error conditions
- ✅ Keep tests simple and focused
- ✅ CI/CD pipelines welcome for automation

## Git & Version Control

### Commit Messages
```
# GOOD - Clear and concise
Simplify to Unix philosophy: minimal implementation
Remove unnecessary abstraction layers
Fix NA handling in empty narratives

# BAD - Vague or too long
Update code
Fixed stuff
Refactored the entire IPV detection system to use...
```

### Branch Names
- `main` or `master` - Stable code
- `dev_*` - Development branches
- No complex git-flow

## File Organization

### Directory Philosophy
- Flat is better than nested
- Obvious names better than clever
- User-facing better than hidden

### What Goes Where
```
/docs         # Core implementation
/data-raw     # Input data
/results      # Output data
/logs         # Debugging info
```

## Anti-Patterns to Avoid

### Over-Engineering
```r
# BAD - Factory pattern in R
IPVDetectorFactory <- R6Class("IPVDetectorFactory",
  public = list(
    create = function(type) {
      # Why?
    }
  )
)

# GOOD - Just a function
detect_ipv <- function(text) { }
```

### Premature Abstraction
```r
# BAD - Abstracting too early
create_api_caller <- function(endpoint_factory, auth_manager, ...) { }

# GOOD - Direct and clear
httr2::request(url) |> httr2::req_perform()
```

### Hidden Magic
```r
# BAD - Side effects and global state
.GlobalEnv$.ipv_cache <- list()

# GOOD - Explicit and predictable
result <- detect_ipv(text)
```

## Performance Guidelines

### Don't Optimize Prematurely
- Write clear code first
- Measure if slow
- Optimize only bottlenecks
- User controls optimization

### Let Users Decide
```r
# Single-threaded (default)
results <- lapply(texts, detect_ipv)

# Parallel (user choice)
results <- parallel::mclapply(texts, detect_ipv)
```

## Code Review Checklist

Before accepting code:
1. ✅ Does it remove more than it adds?
2. ✅ Is it minimal and focused?
3. ✅ Does it eliminate special cases?
4. ✅ Can a user understand it in 2 minutes?
5. ✅ Does it maintain backward compatibility?

## Philosophy Reminders

### Always Remember
- **Simplicity > Features**
- **Clarity > Cleverness**  
- **User Control > Framework Magic**
- **Minimal > Complex**

### Never Forget
> "Programs must be written for people to read, and only incidentally for machines to execute." - SICP

But also:

> "Talk is cheap. Show me the code." - Linus Torvalds

This project shows the code. Minimal. Done.