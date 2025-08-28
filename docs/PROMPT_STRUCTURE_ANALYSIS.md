# IPV Detection Prompt Structure Analysis

## Overview
This document explains the proper separation of system and user prompts for IPV detection, the enhanced `call_llm()` function, and the new `build_ipv_prompt()` helper function.

## Prompt Structure Analysis

### Original Test Prompt Issues
The original `/tests/test_promt.txt` file mixed system-level instructions with user prompts:
- **Lines 1-2**: System instructions (role definition + JSON requirement)  
- **Lines 4-21**: User prompt (analysis request + narrative + format)

### Proper Separation
**System Prompt** (defines AI role and behavior):
```
You are a forensic death investigation analyst specializing in intimate partner violence cases. Conduct systematic analysis through multiple phases: death classification, directionality assessment, suicide analysis, evidence hierarchy, temporal patterns, and quality control. Respond only with valid JSON.
```

**User Prompt** (specific analysis request):
```
Analyze this narrative for intimate partner violence indicators.
Look for ALL potential IPV indicators:
[detailed indicator categories]

Narrative: '[actual narrative text]'

Respond with JSON: { ... }
```

## Enhanced Functions

### 1. Enhanced `call_llm()` Function

**New Parameter:**
- `system_prompt = NULL` - Optional system-level instructions

**Key Features:**
- **Backward Compatible**: Existing code works unchanged
- **Proper Message Structure**: Builds OpenAI-compatible messages array
- **Input Validation**: Validates both prompt and system_prompt parameters

**Usage:**
```r
# Method 1: With system prompt (recommended)
response <- call_llm(user_prompt, system_prompt = system_prompt)

# Method 2: Backward compatible (legacy)  
response <- call_llm(single_combined_prompt)
```

### 2. New `build_ipv_prompt()` Helper Function

**Purpose:** Creates properly structured system and user prompts for IPV detection

**Parameters:**
- `narrative` - The death narrative text to analyze
- `include_json_instruction = TRUE` - Whether to add JSON-only instruction

**Returns:** List with `system` and `user` prompt components

**Usage:**
```r
prompts <- build_ipv_prompt(narrative_text)
response <- call_llm(prompts$user, system_prompt = prompts$system)
```

## Implementation Benefits

### 1. Technical Benefits
- **Proper Role Separation**: Clear distinction between AI role and task
- **Better LLM Performance**: System prompts are processed differently by models
- **Cleaner Architecture**: Separates concerns properly
- **Reusable Components**: System prompt can be reused across different narratives

### 2. Practical Benefits
- **Consistent Behavior**: System role remains stable across requests
- **Easier Debugging**: Can modify system vs user prompts independently
- **Better Prompt Engineering**: Follows LLM best practices
- **Maintainable Code**: Clear separation of prompt components

## Usage Patterns

### Single Analysis
```r
# Load functions
source("R/call_llm.R")

# Build prompts
narrative <- "Death investigation narrative text..."
prompts <- build_ipv_prompt(narrative)

# Make API call
response <- call_llm(prompts$user, system_prompt = prompts$system)
result <- response$choices[[1]]$message$content
```

### Batch Processing  
```r
# Process multiple narratives
results <- lapply(narratives, function(narrative) {
  prompts <- build_ipv_prompt(narrative)
  response <- call_llm(prompts$user, system_prompt = prompts$system)
  response$choices[[1]]$message$content
})
```

### Custom System Prompts
```r
# Custom forensic role
custom_system <- "You are a medical examiner specializing in forensic pathology. Focus on physical evidence only."
user_prompt <- "Analyze this autopsy report for IPV indicators..."

response <- call_llm(user_prompt, system_prompt = custom_system)
```

## Migration Guide

### For Existing Code
No changes needed - the enhanced `call_llm()` is fully backward compatible:

```r
# This still works exactly as before
response <- call_llm("Combined system and user prompt text")
```

### For New Code  
Use the new structure for better results:

```r
# Old way (still works)
combined_prompt <- "You are a forensic analyst. Analyze this narrative..."
response <- call_llm(combined_prompt)

# New way (recommended)
prompts <- build_ipv_prompt(narrative)  
response <- call_llm(prompts$user, system_prompt = prompts$system)
```

## Files Modified

1. **`R/call_llm.R`** - Enhanced with system prompt support and helper function
2. **`tests/test_promt.txt`** - Updated to show proper prompt separation
3. **`examples/prompt_structure_demo.R`** - Complete usage examples
4. **`tests/test_enhanced_prompts.R`** - Validation tests

## Testing

Run the validation tests:
```bash
Rscript tests/test_enhanced_prompts.R
```

All tests pass, confirming:
- ✓ Proper prompt structure creation
- ✓ Input validation works correctly  
- ✓ Backward compatibility maintained
- ✓ Message array built correctly

## Philosophy Alignment

This enhancement follows the Unix philosophy:
- **Single Responsibility**: Each function has one clear purpose
- **Composable**: Functions work together simply
- **Minimal Interface**: Optional parameters, backward compatible
- **User Control**: User decides how to structure their prompts

The implementation adds capability without complexity, maintaining the project's minimalist approach while enabling better LLM interactions.