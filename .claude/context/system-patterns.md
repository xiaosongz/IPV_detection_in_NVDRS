---
created: 2025-08-27T21:35:45Z
last_updated: 2025-08-27T21:35:45Z
version: 1.0
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

### Current Pattern: Pure Function
```r
detect_ipv <- function(text, config = NULL) {
  # Input validation
  # API call
  # Output transformation
  # Error handling
}
```

**Characteristics**:
- No side effects
- Predictable output
- Self-contained
- Testable in isolation

### Anti-Patterns Removed
- ❌ **Over-Engineering** - Removed 10,000+ lines of abstraction
- ❌ **Framework Lock-in** - No required workflow
- ❌ **Hidden Complexity** - No magic methods or inheritance
- ❌ **Premature Optimization** - Let user decide when/how to optimize

## Data Flow Pattern

```
Text Input → detect_ipv() → LLM API → JSON Response → R List
```

### Input Processing
1. Accept text (string)
2. Trim whitespace
3. Check for empty/NA
4. Pass to API

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
detect_ipv(text, config)
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
results <- lapply(texts, detect_ipv)
```

#### Parallel Processing
```r
results <- parallel::mclapply(texts, detect_ipv)
```

#### With Progress
```r
results <- pbapply::pblapply(texts, detect_ipv)
```

#### With Retry
```r
safe_detect <- function(text) {
  result <- detect_ipv(text)
  if (!is.null(result$error)) {
    Sys.sleep(1)
    result <- detect_ipv(text)
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
- `ULTIMATE_CLEAN.R` - Minimal implementation
- `CLEAN_IMPLEMENTATION.R` - Extended features
- User files - Custom workflows

## Testing Pattern

### User-Controlled Testing
```r
# User writes their own tests
test_result <- detect_ipv("test narrative")
stopifnot(is.list(test_result))
stopifnot(names(test_result) %in% c("detected", "confidence"))
```

**Philosophy**:
- No test framework required
- User validates as needed
- Simple assertions sufficient

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