# Experiment ID Guide

## Your Questions Answered

### Q1: How can I know the prompts and model used in experiment ID `60376368-2f1b-4b08-81a9-2f0ea815cd21`?

**Answer:** Use the new `view_experiment.R` script:

```bash
Rscript scripts/view_experiment.R 60376368-2f1b-4b08-81a9-2f0ea815cd21
```

Or to view the latest experiment:
```bash
Rscript scripts/view_experiment.R latest
```

### Q2: Why is the experiment ID so long?

**Answer:** It's a **UUID (Universally Unique Identifier)** - specifically a UUID v4.

**Purpose:**
- Globally unique across all experiments, ever
- No collisions even with parallel experiments
- No coordination needed between systems
- Sortable chronologically (within same day)
- Industry standard for distributed systems

**Format:** `60376368-2f1b-4b08-81a9-2f0ea815cd21`
- 32 hexadecimal characters (128 bits)
- Grouped as: 8-4-4-4-12
- Generated randomly with cryptographic guarantees

**Benefits over sequential IDs:**
1. No race conditions in parallel experiments
2. Can't guess other experiment IDs (privacy)
3. Works offline (no DB lookup needed to generate)
4. Universally recognized format

**Trade-offs:**
- Longer than sequential (1, 2, 3...)
- Not human-memorable
- Slightly larger storage (36 bytes vs ~10)

**Good news:** You rarely type them! Use:
- `Rscript scripts/view_experiment.R latest` (most common)
- Database queries by experiment name
- Tab completion in shell
- Copy-paste from previous outputs

## Experiment Details for 60376368-2f1b-4b08-81a9-2f0ea815cd21

### Summary
- **Name:** Test GPT-OSS-120B new prompt 2025-10-03
- **Model:** mlx-community/gpt-oss-120b
- **Temperature:** 0.2
- **Status:** Completed successfully
- **Runtime:** 26.5 minutes (1590 seconds)
- **Cases:** 404 narratives processed

### Performance Metrics
- **Accuracy:** 94.06%
- **Precision:** 76.09%
- **Recall:** 72.92%
- **F1 Score:** 0.745

### Prompts Used

**System Prompt:**
```
/think hard!
ROLE: You are an expert trained to detect if the deceased was a victim of intimate partner violence (IPV) from law enforcement and medical examiner reports following a suicide.  

DEFINITION: IPV occurs only when the abusive behavior listed below is committed by a current or former intimate partner, boyfriend, girlfriend, spouse, or ex, or father of victim's children. Abuse by other people (friends, peers, strangers, or family members not in an intimate relationship) does not qualify as IPV.  

TYPES OF IPV ABUSE: 
1. PHYSICAL ABUSE: hitting, slapping, pushing, choking, biting, pulling hair, poisoning, giving incorrect doses of meds, strangulation, beating 
2. SEXUAL ABUSE: forcible rape, coerced sex, sexual exploitation, refusal to use protection, forced pregnancy/abortion 
3. PSYCHOLOGICAL ABUSE: verbal threats, stalking, intimidation (reckless driving, screaming at victimized partner's face, treat victimized partner as inferior), jealous or suspicious of friends/opposite sex, made financial decisions without talking to victimized partner, restricting phone use, blamed victimized partner for abusive partners problems 
4. EMOTIONAL ABUSE: gaslighting, lying, providing misinformation, withholding information, isolation (telling victim not to tell anyone about what's happening, not allow victim to socialize, silent treatment), humiliation, using children against victimized partner, sharing intimate nude photos of victimized partner to others without their knowledge. 
5. ECONOMIC ABUSE: control access to money, control access to means of transportation, control whether victimized partner goes to work/school, ruins credit, spends or gambles victimized partners money 
6. LEGAL ABUSE: threat to call police on victimized partner, use court system against victimized partner (i.e. custody change), threaten to call child services, immigration or other governmental agencies
```

**User Template:**
```
TASK: Review the following report narrative and determine: 

Whether IPV is present (true/false). Only mark "TRUE" if the abuse was committed by a current/former intimate partner or father of victim's children. Also mark "TRUE" if victim was ever in a women's shelter (i.e. Family Violence Project). 
Assign confidence (0.00–1.00). 
Briefly justify your rationale in one sentence. 
Narrative:  <<TEXT>>

Return ONLY this JSON:
{
  "detected": true/false,
  "confidence": 0.00-1.00,
  "rationale": "200 char fact-based explanation"
}
```

**Prompt Version:** v0.2.1_April  
**Prompt Author:** Xiaosong

### Configuration
- **API URL:** http://localhost:1234/v1/chat/completions
- **Provider:** mlx
- **Data File:** data-raw/suicide_IPV_manuallyflagged.xlsx
- **Seed:** 1024

### Output Files
- **CSV:** `benchmark_results/experiment_60376368-2f1b-4b08-81a9-2f0ea815cd21_20251003_195912.csv`
- **JSON:** `benchmark_results/experiment_60376368-2f1b-4b08-81a9-2f0ea815cd21_20251003_195912.json`
- **Logs:** `logs/experiments/60376368-2f1b-4b08-81a9-2f0ea815cd21/`

### Confusion Matrix
- True Positives: 35
- True Negatives: 345
- False Positives: 11
- False Negatives: 13

## Quick Reference Commands

### View Experiment Details
```bash
# View latest experiment
Rscript scripts/view_experiment.R latest

# View specific experiment
Rscript scripts/view_experiment.R <experiment-id>

# List recent experiments (no args shows last 10)
Rscript scripts/view_experiment.R
```

### Query Database Directly
```bash
# Connect to database
sqlite3 data/experiments.db

# List all experiments
SELECT experiment_id, experiment_name, model_name, status, start_time 
FROM experiments 
ORDER BY start_time DESC;

# Get experiment by name pattern
SELECT * FROM experiments 
WHERE experiment_name LIKE '%GPT-OSS%';

# Get experiments by model
SELECT * FROM experiments 
WHERE model_name = 'mlx-community/gpt-oss-120b';
```

### In R
```r
library(DBI)
library(RSQLite)
source("R/db_config.R")
source("R/db_schema.R")

# Connect
con <- get_db_connection()

# Query by ID
exp <- dbGetQuery(con, 
  "SELECT * FROM experiments WHERE experiment_id = ?",
  params = list("60376368-2f1b-4b08-81a9-2f0ea815cd21")
)

# Query by name
exp <- dbGetQuery(con, 
  "SELECT * FROM experiments WHERE experiment_name LIKE '%GPT-OSS%'"
)

# Get latest
exp <- dbGetQuery(con,
  "SELECT * FROM experiments ORDER BY start_time DESC LIMIT 1"
)

dbDisconnect(con)
```

## Understanding Experiment IDs

### What's Stored in Each ID?

Each UUID maps to a complete experiment record containing:

1. **Configuration**
   - Model name and provider
   - Temperature, API URL
   - Prompt templates (system + user)
   - Prompt version and author

2. **Data**
   - Source data file
   - Number of narratives
   - Seed for reproducibility

3. **Results**
   - Individual case results (in separate table)
   - Aggregate metrics (accuracy, precision, recall, F1)
   - Confusion matrix values

4. **Timing**
   - Start and end timestamps
   - Total runtime
   - Average time per narrative

5. **Metadata**
   - Experiment name (human-readable)
   - Output file paths
   - Log directory
   - System info (R version, OS, hostname)
   - Status (running, completed, failed, cancelled)

### Database Schema

The experiment ID is the **primary key** that links:
- `experiments` table (1 row per experiment)
- `experiment_results` table (404 rows for your case - one per narrative)
- Output files (CSV, JSON, logs)

```
experiments.experiment_id (PRIMARY KEY)
    ↓
experiment_results.experiment_id (FOREIGN KEY)
    ↓ 
Individual case results (narrative_id, detected, confidence, etc.)
```

## Practical Usage

### When to Use Full ID
- Querying specific experiments
- Referencing in papers/reports
- Comparing across systems
- Archiving results

### When to Use Shortcuts
- Daily work: `latest`
- Quick checks: `view_experiment.R` (lists recent)
- Filtering: Query by name, model, or date

### Best Practices
1. **Always use `view_experiment.R`** first - it's easier than remembering/typing IDs
2. **Use experiment names** for human communication ("GPT-OSS baseline run")
3. **Use UUIDs** for programmatic access (scripts, database queries)
4. **Tab completion** works in most shells: `view_experiment.R 6037<TAB>`
5. **Copy-paste** from database queries or log output

## Why This Matters

**Reproducibility:** Every detail needed to reproduce the experiment is stored with the UUID.

**Traceability:** You can trace any result file back to exact configuration used.

**Comparison:** Compare experiments by querying database with any criteria (model, date, performance).

**Audit Trail:** Complete history of what was run, when, with what configuration, and what results.

## Examples

### Find High-Performing Experiments
```sql
SELECT experiment_id, experiment_name, model_name, f1_ipv, accuracy
FROM experiments 
WHERE f1_ipv > 0.70 
ORDER BY f1_ipv DESC;
```

### Compare Same Model, Different Prompts
```sql
SELECT experiment_id, prompt_version, f1_ipv, accuracy
FROM experiments 
WHERE model_name = 'mlx-community/gpt-oss-120b'
ORDER BY start_time;
```

### Find Failed Experiments
```sql
SELECT experiment_id, experiment_name, status, start_time
FROM experiments 
WHERE status = 'failed'
ORDER BY start_time DESC;
```

---

**Bottom Line:** The long UUID is your friend - it guarantees uniqueness and enables complete traceability. Use the helper scripts to avoid typing them manually!
