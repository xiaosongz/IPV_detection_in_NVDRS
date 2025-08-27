---
created: 2025-08-27T21:35:45Z
last_updated: 2025-08-27T21:35:45Z
version: 1.0
author: Claude Code PM System
---

# Product Context

## Product Definition
**IPV Detection Tool** - A simple function that identifies intimate partner violence indicators in death investigation narratives

## Target Users

### Primary Users
1. **Public Health Researchers**
   - Need: Identify IPV patterns in mortality data
   - Skill Level: R proficiency, statistical analysis
   - Volume: Thousands of narratives

2. **Epidemiologists**
   - Need: Surveillance of IPV-related deaths
   - Skill Level: Data analysis, public health
   - Volume: Population-level datasets

3. **Medical Examiners/Coroners**
   - Need: Flag potential IPV cases for review
   - Skill Level: Medical expertise, basic data tools
   - Volume: Hundreds of cases

### Secondary Users
1. **Policy Analysts** - Inform prevention strategies
2. **Grant Researchers** - Support funding proposals
3. **Public Health Departments** - Local surveillance

## Core Functionality

### What It Does
- **Accepts**: Text narrative about a death
- **Analyzes**: Content for IPV indicators
- **Returns**: Detection result (TRUE/FALSE) and confidence score

### What It Doesn't Do
- ❌ Make legal determinations
- ❌ Replace manual review
- ❌ Provide medical diagnosis
- ❌ Store or manage data

## Use Cases

### Primary Use Case
```r
# Researcher analyzing NVDRS narratives
narrative <- "Victim shot by ex-husband during custody dispute..."
result <- detect_ipv(narrative)
# result$detected = TRUE, confidence = 0.85
```

### Batch Analysis
```r
# Epidemiologist processing annual data
data <- readxl::read_excel("nvdrs_2024.xlsx")
data$ipv_flag <- lapply(data$narrative, detect_ipv)
```

### Validation Study
```r
# Comparing automated detection to manual coding
manual_flags <- data$expert_ipv_flag
auto_flags <- sapply(data$narrative, function(x) detect_ipv(x)$detected)
accuracy <- sum(manual_flags == auto_flags) / length(manual_flags)
```

## Data Sources

### National Violent Death Reporting System (NVDRS)
- **Type**: CDC surveillance system
- **Content**: Death investigation narratives
- **Sources**: Law enforcement (LE) and Coroner/Medical Examiner (CME)
- **Coverage**: Multiple U.S. states
- **Format**: Text narratives with structured data

### Narrative Types
1. **Law Enforcement (LE)**
   - Investigation details
   - Witness statements
   - Scene descriptions

2. **Coroner/Medical Examiner (CME)**
   - Medical findings
   - Autopsy results
   - Death circumstances

## Value Proposition

### For Researchers
- **Speed**: Process thousands of narratives in minutes
- **Consistency**: Same criteria applied uniformly
- **Scalability**: Handle growing datasets

### For Public Health
- **Surveillance**: Identify IPV trends
- **Prevention**: Inform intervention strategies
- **Research**: Enable large-scale studies

## Success Metrics

### Technical Metrics
- **Accuracy**: ~70% agreement with manual coding
- **Speed**: 2-5 narratives per second
- **Reliability**: Consistent results across runs

### User Metrics
- **Adoption**: Number of researchers using tool
- **Volume**: Narratives processed
- **Impact**: Studies published using tool

## Constraints

### Technical Constraints
- Requires LLM API access
- Token limits on narrative length
- API rate limits

### Ethical Constraints
- Sensitive content (violence, death)
- Privacy considerations
- Not for diagnostic use

### Legal Constraints
- Research use only
- No clinical decisions
- Data use agreements required

## Competitive Landscape

### Alternative Approaches
1. **Manual Coding** - Gold standard but slow/expensive
2. **Rule-Based NLP** - Fast but less accurate
3. **Commercial Tools** - Expensive, less transparent

### Our Differentiation
- **Simple**: One function, no complexity
- **Transparent**: Open source, clear logic
- **Flexible**: User controls everything
- **Free**: No licensing costs

## Product Evolution

### Current State (v1.0)
- Single function implementation
- Basic IPV detection
- Manual configuration

### Potential Enhancements (User-Driven)
- Multiple LLM providers
- Custom prompt templates
- Confidence thresholds
- Batch optimization

### Non-Goals
- ❌ Building a platform
- ❌ Creating a service
- ❌ Managing user data
- ❌ Providing UI/dashboard