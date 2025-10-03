# CLAUDE.md

**THE TRUTH**: GOOD TASTE is the KEY!
USE Tidyverse style guide!

> Think carefully and implement the most concise solution that changes as little code as possible.


## The Only File That Matters

`docs/ULTIMATE_CLEAN.R` - Minimal implementation that does everything. Read it. Use it. Done.

## What This Project Actually Does

```r
detect_ipv("text") → {detected: TRUE/FALSE, confidence: 0-1}
```

That's it. One function, one purpose.

## USE SUB-AGENTS FOR CONTEXT OPTIMIZATION

### 1. Always use the file-analyzer sub-agent when asked to read files.
The file-analyzer agent is an expert in extracting and summarizing critical information from files, particularly log files and verbose outputs. It provides concise, actionable summaries that preserve essential information while dramatically reducing context usage.

### 2. Always use the code-analyzer sub-agent when asked to search code, analyze code, research bugs, or trace logic flow.

The code-analyzer agent is an expert in code analysis, logic tracing, and vulnerability detection. It provides concise, actionable summaries that preserve essential information while dramatically reducing context usage.

### 3. Always use the test-runner sub-agent to run tests and analyze the test results.

Using the test-runner agent ensures:

- Full test output is captured for debugging
- Main conversation stays clean and focused
- Context usage is optimized
- All issues are properly surfaced
- No approval dialogs interrupt the workflow

## Rules When Working Here

1. **Never Add Complexity** - If you're adding classes, methods, or abstractions, STOP.
2. **trimws() Everything** - Text always has trailing spaces. Deal with it.
3. **Let Users Control** - They decide loops, parallelization, error handling. Not you.
4. **Keep It Minimal** - Focus on simplicity and clarity over arbitrary line counts.
5. **One Function Per File** - Never append functions to existing files. Create separate R files.

## ABSOLUTE RULES

- NO PARTIAL IMPLEMENTATION
- NO SIMPLIFICATION : no "//This is simplified stuff for now, complete implementation would blablabla"
- NO CODE DUPLICATION : check existing codebase to reuse functions and constants Read files before writing new functions. Use common sense function name to find them easily.
- NO DEAD CODE : either use or delete from codebase completely
- IMPLEMENT TEST FOR EVERY FUNCTIONS
- NO CHEATER TESTS : test must be accurate, reflect real usage and be designed to reveal flaws. No useless tests! Design tests to be verbose so we can use them for debugging.
- NO INCONSISTENT NAMING - read existing codebase naming patterns.
- NO OVER-ENGINEERING - Don't add unnecessary abstractions, factory patterns, or middleware when simple functions would work. Don't think "enterprise" when you need "working"
- NO MIXED CONCERNS - Don't put validation logic inside API handlers, database queries inside UI components, etc. instead of proper separation
- NO RESOURCE LEAKS - Don't forget to close database connections, clear timeouts, remove event listeners, or clean up file handles

## Git Commit Best Practices (MANDATORY)

When working on GitHub issues:
1. **Create feature branch**: `git checkout -b issue-{number}` before starting work
2. **Commit frequently**: Small, focused commits with clear messages
3. **Reference issues**: Always use "Issue #{number}: {description}" format
4. **Test before commit**: Run tests, ensure code works
5. **Close issues properly**: Use "Closes #{number}" in final commit
6. **Never leave work uncommitted**: Every completed issue MUST have commits

Example workflow:
```bash
git checkout -b issue-4              # Start new feature branch
# ... do work ...
git add R/new_function.R
git commit -m "Issue #4: Add database schema"
# ... more work ...
git commit -m "Issue #4: Add connection utilities"
git commit -m "Issue #4: Complete implementation - Closes #4"
git checkout dev_c                   # Return to main branch
git merge --no-ff issue-4           # Merge with history
```

## File Structure (What Actually Matters)

```
docs/ULTIMATE_CLEAN.R      # THE minimal implementation
docs/CLEAN_IMPLEMENTATION.R # If you REALLY need batching
data-raw/*.xlsx            # Test data
R/*.R                      # Package functions
tests/testthat/*.R         # Test files
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

### Error Handling

- **Fail fast** for critical configuration (missing text model)
- **Log and continue** for optional features (extraction model)
- **Graceful degradation** when external services unavailable
- **User-friendly messages** through resilience layer

### Testing

- Always use the test-runner agent to execute tests.
- Do not use mock services for anything ever.
- Do not move on to the next test until the current test is complete.
- If the test fails, consider checking if the test is structured correctly before deciding we need to refactor the codebase.
- Tests to be verbose so we can use them for debugging.

## When Someone Asks for Features

Default answer: "Write it yourself. The function is minimal and simple. Fork it if you want complexity."

## The Linus Test

Before any change, ask:
1. Does this eliminate a special case? (Good)
2. Does this add a special case? (Reject)
3. Can this be done in user space? (Then don't add it)
4. Will this break existing usage? (Never)

If you're adding error recovery, retry logic, or progress bars - STOP. Users can wrap the function however they want. That's the Unix way.

## Tone and Behavior

- Criticism is welcome. Please tell me when I am wrong or mistaken, or even when you think I might be wrong or mistaken.
- Please tell me if there is a better approach than the one I am taking.
- Please tell me if there is a relevant standard or convention that I appear to be unaware of.
- Be skeptical.
- Be concise.
- Short summaries are OK, but don't give an extended breakdown unless we are working through the details of a plan.
- Do not flatter, and do not give compliments unless I am specifically asking for your judgement.
- Occasional pleasantries are fine.
- Feel free to ask many questions. If you are in doubt of my intent, don't guess. Ask.