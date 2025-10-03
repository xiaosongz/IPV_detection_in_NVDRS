# Experiment Configuration Guide

Quick reference for creating and customizing experiment YAML configs.

---

## 📋 Required Keys

Every config must have these sections:

```yaml
experiment:
  name: "Your Experiment Name"        # Required: Descriptive name
  author: "your_name"                 # Required: Who ran it
  notes: "Purpose and context"        # Required: Why this experiment

model:
  name: "mlx-community/gpt-oss-120b" # Required: Model identifier
  provider: "mlx"                     # Required: mlx, openai, anthropic
  api_url: "http://localhost:1234/v1/chat/completions"  # Required: API endpoint
  temperature: 0.2                    # Required: 0.0-1.0 (lower = more deterministic)

prompt:
  version: "v2.1_andrea"              # Required: Version identifier
  system_prompt: |                    # Required: System instructions
    Your system prompt here
  user_template: |                    # Required: User message template
    Your template with <<TEXT>> placeholder

data:
  file: "data-raw/your_file.xlsx"    # Required: Path to data file

run:
  seed: 123                           # Required: For reproducibility
  max_narratives: 10                  # Optional: Limit processing (omit for all)
  save_incremental: true              # Optional: Save after each narrative
  save_csv_json: true                 # Optional: Export results to CSV/JSON
```

---

## 🎯 Key Explanations

### experiment
- **name**: Short, descriptive name for this run (used in logs and queries)
- **author**: Your identifier (for tracking who ran what)
- **notes**: Free text explaining purpose, changes from previous runs, etc.

### model
- **name**: Model identifier (must match what your API expects)
- **provider**: API type (mlx, openai, anthropic) - affects request format
- **api_url**: Full URL to API endpoint (include /v1/chat/completions for OpenAI-compatible)
- **temperature**: Controls randomness
  - `0.0` = deterministic (same input → same output)
  - `0.2` = slightly random (recommended for classification)
  - `0.7` = creative (not recommended for detection tasks)
  - `1.0` = very random

### prompt
- **version**: Label for this prompt iteration (e.g., "v2.1_andrea", "v3.0_test")
- **system_prompt**: Instructions for the model (role, scope, indicators)
- **user_template**: Message sent per narrative
  - **MUST contain `<<TEXT>>`** - This is replaced with actual narrative text
  - Use `|` for multi-line text (YAML syntax)

### data
- **file**: Path to Excel file with narratives
  - Relative to project root (e.g., "data-raw/file.xlsx")
  - Must have required columns (see data loader docs)

### run
- **seed**: Random seed for reproducibility (any integer)
- **max_narratives**: Limit processing to first N narratives
  - Useful for testing (start with 10)
  - Omit or set to large number for full dataset
- **save_incremental**: Save to database after each narrative
  - `true` = slower but safer (can resume if crashes)
  - `false` = faster but lose all if crashes
- **save_csv_json**: Export results to files after completion
  - Creates: `results_TIMESTAMP.csv` and `results_TIMESTAMP.json`
  - Useful for sharing results outside database

---

## 📝 The <<TEXT>> Placeholder

**CRITICAL**: Your `user_template` must contain `<<TEXT>>`

This placeholder is replaced with the actual narrative text for each record.

**Correct**:
```yaml
user_template: |
  Analyze this narrative:
  
  <<TEXT>>
  
  Return JSON with detected and confidence.
```

**Wrong** (no placeholder):
```yaml
user_template: |
  Analyze this narrative and return JSON.
```

**Wrong** (typo):
```yaml
user_template: |
  <<NARRATIVE>>  # Should be <<TEXT>>
```

---

## 🎨 Common Customizations

### Change Model
```yaml
model:
  name: "openai/gpt-4"
  provider: "openai"
  api_url: "https://api.openai.com/v1/chat/completions"
  temperature: 0.1
```

### Test with Small Sample
```yaml
run:
  seed: 123
  max_narratives: 5  # Just 5 narratives for quick test
```

### Process Full Dataset
```yaml
run:
  seed: 123
  # max_narratives not specified = all narratives
  save_incremental: true
  save_csv_json: true
```

### Adjust Temperature
```yaml
model:
  temperature: 0.0   # Fully deterministic
  # or
  temperature: 0.1   # Slightly random (good for replication)
  # or
  temperature: 0.5   # More variation (not recommended for detection)
```

### Compare Prompt Versions
```yaml
# Experiment 1
experiment:
  name: "Prompt v2.0 Baseline"
prompt:
  version: "v2.0"
  system_prompt: |
    Old prompt text...

# Experiment 2  
experiment:
  name: "Prompt v2.1 with Enhanced Indicators"
prompt:
  version: "v2.1"
  system_prompt: |
    New prompt with more indicators...
```

---

## 📁 Template Usage

### Quick Start: Copy Existing Config
```bash
# Copy template
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/my_experiment.yaml

# Edit your copy
nano configs/experiments/my_experiment.yaml

# Change:
# - experiment.name
# - experiment.author
# - experiment.notes
# - run.max_narratives (start with 10 for testing)

# Run
Rscript scripts/run_experiment.R configs/experiments/my_experiment.yaml
```

### Create New Config from Scratch
```yaml
experiment:
  name: "My New Experiment"
  author: "yourname"
  notes: "Testing hypothesis X with model Y"

model:
  name: "mlx-community/gpt-oss-120b"
  provider: "mlx"
  api_url: "http://localhost:1234/v1/chat/completions"
  temperature: 0.2

prompt:
  version: "v1.0"
  system_prompt: |
    You are an expert at detecting IPV.
    Follow these rules...
    
  user_template: |
    Analyze this narrative:
    <<TEXT>>
    
    Return JSON: {"detected": bool, "confidence": float}

data:
  file: "data-raw/suicide_IPV_manuallyflagged.xlsx"

run:
  seed: 123
  max_narratives: 10
  save_incremental: true
  save_csv_json: true
```

---

## 🔍 Validation

The config loader validates:
- ✅ All required keys present
- ✅ `<<TEXT>>` placeholder in user_template
- ✅ Temperature between 0.0 and 1.0
- ✅ Data file exists
- ✅ YAML syntax correct

**If validation fails**, you'll get a clear error message:
```
Error: user_template must contain <<TEXT>> placeholder
Config file: configs/experiments/my_experiment.yaml
```

---

## 🎯 Best Practices

### Naming Conventions
- **Configs**: `exp_NNN_description.yaml` (e.g., `exp_001_test_gpt_oss.yaml`)
- **Experiment names**: Clear and searchable (e.g., "GPT-4 Baseline v2.1")
- **Prompt versions**: Semantic versioning (e.g., "v2.1_andrea", "v3.0_test")

### Testing Strategy
1. **Start small**: `max_narratives: 10`
2. **Verify output**: Check logs and database
3. **Adjust prompt**: Based on initial results
4. **Scale up**: `max_narratives: 100` or remove limit
5. **Compare**: Run multiple configs, query database to compare

### Temperature Guidelines
| Temperature | Use Case | Reproducibility |
|------------|----------|-----------------|
| 0.0 | Perfect replication | 100% same |
| 0.1 | Near-perfect replication | 95% same |
| 0.2 | Slight variation (default) | 90% same |
| 0.5 | Moderate variation | 70% same |
| 1.0 | High variation (avoid!) | 40% same |

**For IPV detection**: Use 0.0-0.2

### Documentation
- Always fill `experiment.notes` with:
  - What you're testing
  - How this differs from previous runs
  - Expected outcomes
- This makes database queries much more useful later

---

## 📊 Example: A/B Testing

### Experiment A: Baseline
```yaml
# configs/experiments/exp_010_baseline.yaml
experiment:
  name: "Baseline Model - GPT-OSS"
  author: "researcher1"
  notes: "Baseline performance with v2.1 prompt, temp=0.2"

model:
  name: "mlx-community/gpt-oss-120b"
  temperature: 0.2
# ... rest of config
```

### Experiment B: Low Temperature
```yaml
# configs/experiments/exp_011_low_temp.yaml
experiment:
  name: "Low Temperature - GPT-OSS"
  author: "researcher1"
  notes: "Same as baseline but temp=0.0 for perfect reproducibility"

model:
  name: "mlx-community/gpt-oss-120b"
  temperature: 0.0  # Only change
# ... rest same as baseline
```

### Compare Results
```r
library(DBI)
library(RSQLite)

conn <- dbConnect(SQLite(), "data/experiments.db")

# Get metrics for both
dbGetQuery(conn, "
  SELECT 
    name,
    temperature,
    precision,
    recall,
    f1_score
  FROM experiments
  WHERE name IN ('Baseline Model - GPT-OSS', 'Low Temperature - GPT-OSS')
")
```

---

## 🚨 Common Mistakes

### ❌ Missing <<TEXT>>
```yaml
user_template: |
  Analyze this narrative.  # ERROR: No <<TEXT>>
```

### ❌ Wrong Placeholder
```yaml
user_template: |
  <<NARRATIVE>>  # ERROR: Should be <<TEXT>>
```

### ❌ Temperature Out of Range
```yaml
temperature: 1.5  # ERROR: Must be 0.0-1.0
```

### ❌ Invalid YAML Syntax
```yaml
prompt:
  system_prompt: Multi-line text
    without pipe character  # ERROR: Need |
```

### ❌ File Path Not Relative
```yaml
data:
  file: "/absolute/path/file.xlsx"  # WARNING: Not portable
  # Better: "data-raw/file.xlsx"
```

---

## 📚 See Also

- **exp_001_test_gpt_oss.yaml** - Working template
- **docs/20251003-unified_experiment_automation_plan.md** - Full system docs
- **R/config_loader.R** - Validation code

---

**Questions?** The config loader will tell you exactly what's wrong if validation fails!
