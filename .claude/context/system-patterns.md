---
created: 2025-08-27T21:35:45Z
last_updated: 2025-08-28T14:15:08Z
version: 1.3
author: Claude Code PM System
---

# System Patterns

## Architectural Style
**Unix Philosophy** - Do one thing and do it well

### Core Principles
1. **Single Responsibility** - One function, one purpose
2. **Composability** - User combines simple tools
3. **Text Streams** - Simple input/output
4. **No Magic** - Explicit, understandable behavior

## Design Patterns

### Data Persistence Pattern

**Hybrid Design: Simple + Experimental**

**Production Mode (Default)**
- **Single Table**: `llm_results` with all fields
- **Zero Configuration**: Works out of the box
- **Performance**: >1000 inserts/second

**Experiment Mode (Optional)**
- **4-Table Schema**: prompts, experiments, results, ground_truth
- **Version Control**: Automatic prompt deduplication
- **Statistical Analysis**: Built-in A/B testing and metrics
- **Opt-in Complexity**: Only use when needed

## Implementation Patterns

### Current Pattern: Pipeline Architecture
```r
# 1. Message formatting (pure function)
build_prompt <- function(system_prompt, user_prompt) {
  # Input validation
  # Message structure creation
  # Return formatted messages
}

# 2. API interface (I/O function) 
call_llm <- function(user_prompt, system_prompt, ...) {
  # Input validation
  # Call build_prompt() for messages
  # API call
  # Error handling
}

# 3. Response parsing (pure function)
parse_llm_result <- function(response, narrative_id = NULL) {
  # Parse JSON response
  # Extract structured fields
  # Handle errors gracefully
  # Return standardized structure
}

# 4. Storage layer (I/O function)
store_llm_result <- function(parsed_result, conn = NULL) {
  # Connect to SQLite
  # Insert parsed data
  # Handle duplicates
  # Return success status
}
```

**Characteristics**:
- **Pipeline Processing**: Data flows through discrete stages
- **Separation of Concerns**: Each function has single responsibility
- **Database Abstraction**: DBI interface for portability
- **Error Resilience**: Each stage handles failures gracefully
- **Composability**: Functions can be used independently or chained
- **Testability**: Each function tested in isolation (200+ test cases)

### Anti-Patterns Removed
- ❌ **Over-Engineering** - No unnecessary abstractions
- ❌ **Hidden Complexity** - No magic methods or inheritance
- ❌ **Premature Optimization** - Let user decide when/how to optimize

## Data Flow Pattern

```
System + User Prompts → build_prompt() → Messages List → call_llm() → LLM API → JSON Response → R List
```

### Input Processing
1. Accept system and user prompts (both required strings)
2. Validate inputs (non-empty, single character strings)
3. Format into messages structure
4. Pass to LLM API

### Output Processing
1. Receive JSON from API
2. Parse with jsonlite
3. Return structured list
4. Handle errors gracefully

## Error Handling Pattern

### Strategy: Fail Gracefully
```r
tryCatch({
  # API call
}, error = function(e) {
  list(detected = NA, confidence = 0, error = e$message)
})
```

**Principles**:
- Never crash the user's session
- Return NA for missing data
- Include error message for debugging
- Let user decide on retry logic

## Configuration Pattern

### Environment Variables First
```r
Sys.getenv("LLM_API_URL", "default_value")
```

### Direct Config Object Second
```r
config <- list(api_url = "...", model = "...")
call_llm(user_prompt, system_prompt, config)
```

**Benefits**:
- No config files to manage
- User controls configuration
- Easy to override per-call
- No hidden settings

## Composition Patterns

### User-Controlled Patterns

#### Sequential Processing
```r
results <- lapply(texts, function(x) call_llm(x, system_prompt))
```

#### Parallel Processing
```r
results <- parallel::mclapply(texts, function(x) call_llm(x, system_prompt))
```

#### With Progress
```r
results <- pbapply::pblapply(texts, function(x) call_llm(x, system_prompt))
```

#### With Retry
```r
safe_call <- function(user_prompt, system_prompt) {
  result <- call_llm(user_prompt, system_prompt)
  if (!is.null(result$error)) {
    Sys.sleep(1)
    result <- call_llm(user_prompt, system_prompt)
  }
  result
}
```

## Code Organization Pattern

### Flat Structure
- No nested modules
- No complex dependencies
- Single file can contain entire solution
- User decides organization

### File Responsibility
- `R/call_llm.R` - Core LLM interface function
- `R/parse_llm_result.R` - Response parsing
- `R/store_llm_result.R` - Storage layer
- `R/experiment_*.R` - Research tracking
- User files - Custom workflows

## Testing Pattern

### Comprehensive Testing with testthat
```r
# Professional testing with testthat
test_that("call_llm handles valid input correctly", {
  test_result <- call_llm("test narrative", "Detect IPV")
  expect_type(test_result, "list")
  expect_true("response" %in% names(test_result))
})

test_that("call_llm handles errors gracefully", {
  result <- call_llm("", "Detect IPV")
  expect_true(!is.null(result$error) || is.na(result$detected))
})
```

**Philosophy**:
- Professional testing with testthat
- Test edge cases and error conditions
- Ensure functions work correctly in isolation
- CI/CD integration for continuous quality

## Performance Patterns

### Lazy Evaluation
- Don't preload anything
- Don't cache unless user wants
- Don't optimize prematurely

### Resource Management
- No persistent connections
- No global state
- Each call independent
- User manages resources

## Integration Patterns

### API Integration
- RESTful HTTP calls
- JSON request/response
- Stateless communication
- Standard protocols

### Data Integration  
- Accept any text source
- Return standard R structures
- User controls I/O
- No format assumptions

## Scalability Pattern

### Horizontal Scaling
User can:
- Run multiple R sessions
- Use compute clusters
- Parallelize with any method
- Batch as they prefer

### No Framework Scaling
- No built-in queue
- No job management
- No progress tracking
- User implements what they need