# Quick Start Guide

**Get running in 5 minutes**. Full details in archived docs if needed.

---

## 🎯 Prerequisites

1. **R installed** (4.0+)
2. **LLM API running** at `http://localhost:1234/v1/chat/completions`
   - Or update API URL in config
3. **Data file** at `data-raw/suicide_IPV_manuallyflagged.xlsx`

---

## 🚀 Three Steps to Run

### 1. Install Required Packages

```r
# Run once
install.packages(c(
  "here", "DBI", "RSQLite", "yaml", "readxl",
  "dplyr", "httr2", "jsonlite", "tibble", "purrr"
))
```

### 2. Copy and Edit Config

```bash
# Copy template
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/my_experiment.yaml

# Edit (optional, template works as-is for testing)
nano configs/experiments/my_experiment.yaml
```

**Key settings to check**:
- `model.api_url`: Your LLM API endpoint
- `model.temperature`: 0.1 (default, good for replication)
- `run.max_narratives`: 10 (start small for testing)

### 3. Run Experiment

```bash
Rscript scripts/run_experiment.R configs/experiments/my_experiment.yaml
```

**That's it!** The script automatically:
- ✅ Creates database (first run)
- ✅ Loads data from Excel (first run)
- ✅ Processes narratives with LLM
- ✅ Computes metrics
- ✅ Saves everything to database

---

## 📊 Check Results

### In R

```r
library(DBI)
library(RSQLite)
library(here)
source(here("R/db_config.R"))

# Connect to database
conn <- dbConnect(SQLite(), get_experiments_db_path())

# List all experiments
dbGetQuery(conn, "
  SELECT 
    experiment_id,
    name,
    precision,
    recall,
    f1_score,
    created_at
  FROM experiments
  ORDER BY created_at DESC
")

# Get detailed results for experiment #1
dbGetQuery(conn, "
  SELECT 
    narrative_id,
    detected,
    confidence,
    ground_truth
  FROM narrative_results
  WHERE experiment_id = 1
")

dbDisconnect(conn)
```

### View Logs

```bash
# Experiment log (overview)
cat logs/experiments/exp_TIMESTAMP/experiment.log

# LLM responses (detailed)
cat logs/experiments/exp_TIMESTAMP/llm_responses.log

# Errors (if any)
cat logs/experiments/exp_TIMESTAMP/errors.log
```

---

## 🎛️ Configuration

### Database Location

**Default**: `data/experiments.db`

**To change**: Edit `.db_config` in project root
```bash
EXPERIMENTS_DB=data/experiments.db      # Default
EXPERIMENTS_DB=/path/to/custom.db       # Custom
```

See: [Database Configuration Guide](20251003-database_configuration_guide.md)

### Experiment Config

**Template**: `configs/experiments/exp_001_test_gpt_oss.yaml`

**Key fields**:
- `experiment.name`: Your experiment name
- `model.api_url`: LLM API endpoint
- `model.temperature`: 0.0-1.0 (use 0.1 for reproducibility)
- `prompt.user_template`: Must contain `<<TEXT>>` placeholder
- `run.max_narratives`: Limit for testing (omit for all)

See: [Config Guide](../configs/experiments/README.md)

---

## 🔍 Troubleshooting

### "Database not found"
```bash
# Database is auto-created on first run
# If deleted, just run script again
Rscript scripts/run_experiment.R config.yaml
```

### "Cannot connect to API"
- Check LLM service is running: `curl http://localhost:1234/v1/models`
- Verify `api_url` in config matches your service

### "Package X not found"
```r
install.packages("X")  # Install missing package
```

### "user_template must contain <<TEXT>>"
- Edit your config's `user_template`
- Add `<<TEXT>>` where narrative text should go

---

## 📁 Project Structure

```
project/
├── .db_config                    # Edit: Database location
├── configs/experiments/          # Edit: Experiment configs
│   ├── README.md                 # Config documentation
│   └── exp_001_test_gpt_oss.yaml # Template
├── data/
│   └── experiments.db            # Results database
├── data-raw/
│   └── suicide_IPV_*.xlsx        # Source data
├── R/                            # Code (don't edit unless developing)
├── scripts/
│   └── run_experiment.R          # Main script
└── logs/experiments/             # Auto-generated logs
```

---

## 🎓 Next Steps

### Run Full Dataset
```yaml
# Edit config: remove or increase max_narratives
run:
  max_narratives: 1000  # Or omit for all
```

### Compare Experiments
```r
# Query database to compare
source(here("R/db_config.R"))
source(here("R/experiment_queries.R"))

conn <- dbConnect(SQLite(), get_experiments_db_path())

# Compare all experiments
list_experiments(conn)

# Detailed comparison
compare_experiments(conn, c(1, 2, 3))

dbDisconnect(conn)
```

### Change Models
```yaml
# Edit config
model:
  name: "openai/gpt-4"
  provider: "openai"
  api_url: "https://api.openai.com/v1/chat/completions"
  temperature: 0.1
```

---

## 📚 Documentation

**Start here** (this file) → For detailed info:

- **Config Reference**: `configs/experiments/README.md`
- **Database Setup**: `docs/20251003-database_configuration_guide.md`
- **Full System**: `docs/20251003-INDEX.md`

---

## ⚡ TL;DR

```bash
# 1. Install packages (once)
Rscript -e "install.packages(c('here','DBI','RSQLite','yaml','readxl','dplyr','httr2','jsonlite'))"

# 2. Copy config
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/test.yaml

# 3. Run
Rscript scripts/run_experiment.R configs/experiments/test.yaml

# 4. Check results
Rscript -e "
  library(DBI); library(RSQLite); library(here)
  source(here('R/db_config.R'))
  conn <- dbConnect(SQLite(), get_experiments_db_path())
  print(dbGetQuery(conn, 'SELECT * FROM experiments'))
  dbDisconnect(conn)
"
```

**Done!** Results in database, logs in `logs/experiments/`.

---

**Questions?** See full docs in `docs/` or config examples in `configs/experiments/README.md`.
