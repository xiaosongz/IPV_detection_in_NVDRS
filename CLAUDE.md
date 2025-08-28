# CLAUDE.md

**THE TRUTH**: This entire project is 30 lines of code. Everything else is noise.

## The Only File That Matters

`docs/ULTIMATE_CLEAN.R` - 30 lines that do everything. Read it. Use it. Done.

## What This Project Actually Does

```r
detect_ipv("text") → {detected: TRUE/FALSE, confidence: 0-1}
```

That's it. One function, one purpose.

## Rules When Working Here

1. **Never Add Complexity** - If you're adding classes, methods, or abstractions, STOP.
2. **trimws() Everything** - Text always has trailing spaces. Deal with it.
3. **Let Users Control** - They decide loops, parallelization, error handling. Not you.
4. **100 Lines Maximum** - If the solution needs more, the problem is wrong.
5. **One Function Per File** - Never append functions to existing files. Create separate R files.

## File Structure (What Actually Matters)

```
docs/ULTIMATE_CLEAN.R      # THE implementation (30 lines)
docs/CLEAN_IMPLEMENTATION.R # If you REALLY need batching (100 lines)
data-raw/*.xlsx            # Test data
Everything else            # Legacy garbage, ignore it
```

## Common Tasks

```r
# Single detection
source("docs/ULTIMATE_CLEAN.R")
result <- detect_ipv("narrative")

# Your own batch processing
data$ipv <- lapply(data$narrative, detect_ipv)

# Your own parallel
library(parallel)
results <- mclapply(texts, detect_ipv, mc.cores = detectCores())
```

## Philosophy

> "Bad programmers worry about the code. Good programmers worry about data structures and their relationships." - Linus Torvalds

This project has ONE data structure: a list with `detected` and `confidence`. Everything else is user's problem.

## When Someone Asks for Features

Default answer: "Write it yourself. The function is 30 lines. Fork it if you want complexity."

## The Linus Test

Before any change, ask:
1. Does this eliminate a special case? (Good)
2. Does this add a special case? (Reject)
3. Can this be done in user space? (Then don't add it)
4. Will this break existing usage? (Never)

If you're adding error recovery, retry logic, or progress bars - STOP. Users can wrap the function however they want. That's the Unix way.