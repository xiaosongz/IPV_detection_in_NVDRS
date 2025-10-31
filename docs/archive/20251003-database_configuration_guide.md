# Database Configuration Guide

**Question**: Where should I save the database? Can I change the location?  
**Answer**: YES! Easy to configure. Read below.

---

## TL;DR - Quick Start

**Database location**: `data/experiments.db` (default)

**To change**: Edit `.db_config` file in project root

```bash
# Edit .db_config
EXPERIMENTS_DB=data/experiments.db          # Relative to project
# or
EXPERIMENTS_DB=/absolute/path/to/my.db      # Absolute path
# or
EXPERIMENTS_DB=~/Documents/research/ipv.db  # Home directory
```

---

## Why data/ Directory?

✅ **Better than root**:
- Cleaner project structure
- Logical organization (data goes in data/)
- Easier to backup (just backup data/)
- Standard practice in R projects

✅ **Properly gitignored**:
- Database is `.gitignored` (won't be committed)
- But directory structure is preserved

✅ **Easy to find**:
```
project/
├── data/
│   ├── experiments.db          ← Your database
│   └── README.md               ← Documentation
├── R/                          ← Code
├── scripts/                    ← Scripts
└── .db_config                  ← Configuration
```

---

## Configuration Methods

### Method 1: Edit .db_config File (RECOMMENDED)

**File**: `.db_config` in project root

```bash
# Database Configuration File
# Edit this file to change database locations

# Main experiments database
EXPERIMENTS_DB=data/experiments.db

# Test database  
TEST_DB=tests/fixtures/test_experiments.db
```

**Examples**:
```bash
# Default (data/ directory)
EXPERIMENTS_DB=data/experiments.db

# Custom name in data/
EXPERIMENTS_DB=data/my_experiments.db

# Absolute path
EXPERIMENTS_DB=/Users/yourname/Databases/ipv.db

# Home directory
EXPERIMENTS_DB=~/Documents/research/experiments.db

# Network drive (if mounted)
EXPERIMENTS_DB=/Volumes/Research/IPV/experiments.db

# External drive
EXPERIMENTS_DB=/Volumes/ExternalDrive/experiments.db
```

### Method 2: Environment Variable (Temporary)

**One-time override**:
```bash
EXPERIMENTS_DB=/tmp/test.db Rscript scripts/run_experiment.R config.yaml
```

**Current session**:
```bash
export EXPERIMENTS_DB=/custom/path/experiments.db
Rscript scripts/run_experiment.R config.yaml
```

### Method 3: In R Code (Programmatic)

```r
# Set before loading config
Sys.setenv(EXPERIMENTS_DB = "/custom/path.db")

# Then use normally
source("R/db_config.R")
db_path <- get_experiments_db_path()
```

---

## Configuration Priority

**Highest to lowest**:

1. **Environment variable** (command line or shell)
   ```bash
   EXPERIMENTS_DB=custom.db Rscript script.R
   ```

2. **.db_config file** (persistent, recommended)
   ```
   EXPERIMENTS_DB=data/experiments.db
   ```

3. **Default value** (if nothing set)
   ```
   data/experiments.db
   ```

---

## Verification

Check your current configuration:

```r
source("R/db_config.R")
print_db_config()
```

Output:
```
========================================
Database Configuration
========================================

Configuration File:
  Location: /path/to/project/.db_config
  Exists: TRUE

Experiments DB:
  Path: /path/to/project/data/experiments.db
  Exists: TRUE
  Size: 688 KB
  Directory: /path/to/project/data

...
========================================
```

---

## Common Scenarios

### Scenario 1: Default Setup (Recommended)

**No changes needed** - just run experiments!

```bash
# Database automatically goes to data/experiments.db
Rscript scripts/run_experiment.R config.yaml
```

### Scenario 2: External Drive

**Use case**: Database on external drive for portability

**Edit .db_config**:
```bash
EXPERIMENTS_DB=/Volumes/MyDrive/IPV_Research/experiments.db
```

**Create directory**:
```bash
mkdir -p /Volumes/MyDrive/IPV_Research
```

**Run normally**:
```bash
Rscript scripts/run_experiment.R config.yaml
```

### Scenario 3: Network Storage

**Use case**: Shared database for team collaboration

**Edit .db_config**:
```bash
EXPERIMENTS_DB=/Volumes/Research/Shared/IPV/experiments.db
```

**⚠️ Warning**: SQLite has limitations with network filesystems. Consider:
- Single user at a time
- Or use PostgreSQL for true multi-user (see advanced docs)

### Scenario 4: Per-Project Databases

**Use case**: Multiple research projects, separate databases

**Project 1**:
```bash
cd /path/to/project1
echo "EXPERIMENTS_DB=data/project1_experiments.db" > .db_config
```

**Project 2**:
```bash
cd /path/to/project2
echo "EXPERIMENTS_DB=data/project2_experiments.db" > .db_config
```

### Scenario 5: Temporary Testing

**Use case**: Don't want to affect production database

```bash
# One-time test with temporary database
EXPERIMENTS_DB=/tmp/test_experiments.db Rscript scripts/run_experiment.R config.yaml

# Production database untouched
```

---

## Backup Strategies

### Strategy 1: Manual Backups

**Before major changes**:
```bash
cp data/experiments.db data/experiments_backup_$(date +%Y%m%d).db
```

**Or use data/backups/ directory**:
```bash
mkdir -p data/backups
cp data/experiments.db data/backups/experiments_$(date +%Y%m%d_%H%M%S).db
```

### Strategy 2: Automated Backups

**Daily cron job** (Linux/Mac):
```bash
# Add to crontab (crontab -e)
0 2 * * * cp /path/to/project/data/experiments.db /path/to/backups/experiments_$(date +\%Y\%m\%d).db
```

### Strategy 3: Cloud Sync

**Dropbox/Google Drive**:
```bash
# Symlink data/ to cloud storage
mv data /Users/you/Dropbox/IPV_Research/
ln -s /Users/you/Dropbox/IPV_Research/data data
```

### Strategy 4: Git LFS (for small databases)

```bash
# Install git-lfs
brew install git-lfs  # Mac
# or: sudo apt install git-lfs  # Linux

# Track backup files
git lfs track "data/backups/*.db"
git add .gitattributes
git commit -m "Track DB backups with git-lfs"

# Now backups can be committed
cp data/experiments.db data/backups/milestone_v1.db
git add data/backups/milestone_v1.db
git commit -m "Backup: Milestone v1"
```

---

## Troubleshooting

### Problem: "Database not found"

**Check configuration**:
```r
source("R/db_config.R")
print_db_config()
```

**Fix**: Ensure path exists or create it:
```bash
mkdir -p data
```

### Problem: "Permission denied"

**Check permissions**:
```bash
ls -l data/
```

**Fix**:
```bash
chmod 755 data
chmod 644 data/experiments.db
```

### Problem: ".db_config not loading"

**Check file location**:
```bash
ls -la .db_config
```

**Must be**: In project root (same level as README.md)

**Check format**:
- No spaces around `=`
- One setting per line
- Comments start with `#`

### Problem: "Database locked"

**Cause**: Another process has database open

**Fix**:
- Close other R sessions
- Check for -shm and -wal files:
  ```bash
  ls data/*.db*
  rm data/*.db-shm data/*.db-wal  # If safe
  ```

---

## Migration Guide

### From Root to data/ Directory

**Already done for you!** But if you have old databases:

```bash
# Move old database
mv experiments.db data/

# Update .db_config (already correct)
cat .db_config
# Should show: EXPERIMENTS_DB=data/experiments.db
```

### From Custom Location

**Scenario**: You had database elsewhere, want to use standard location

1. **Copy database**:
   ```bash
   cp /old/location/experiments.db data/
   ```

2. **Update .db_config**:
   ```bash
   EXPERIMENTS_DB=data/experiments.db
   ```

3. **Verify**:
   ```r
   source("R/db_config.R")
   print_db_config()
   ```

---

## Security Considerations

### ⚠️ Database May Contain Sensitive Data

- Narrative text (potentially PII)
- IPV indicators
- Experimental parameters

### Best Practices

1. **Never commit database to git**
   - ✅ Already in .gitignore
   - ⚠️ Double-check: `git status` should NOT show .db files

2. **Encrypt backups** (if required):
   ```bash
   # Encrypt backup
   gpg -c data/experiments.db
   # Creates: data/experiments.db.gpg
   
   # Decrypt later
   gpg data/experiments.db.gpg
   ```

3. **Control access**:
   ```bash
   chmod 600 data/experiments.db  # Only you can read/write
   ```

4. **Follow institutional policies**:
   - IRB requirements
   - Data retention policies
   - HIPAA/GDPR compliance

---

## Advanced: Multiple Databases

**Use case**: Separate databases for different studies

### Option 1: Multiple .db_config Files

```bash
# Study 1
cp .db_config .db_config.study1
# Edit: EXPERIMENTS_DB=data/study1_experiments.db

# Study 2  
cp .db_config .db_config.study2
# Edit: EXPERIMENTS_DB=data/study2_experiments.db

# Use specific config
cp .db_config.study1 .db_config
Rscript scripts/run_experiment.R config.yaml
```

### Option 2: Environment Variables

```bash
# Study 1
EXPERIMENTS_DB=data/study1.db Rscript scripts/run_experiment.R config1.yaml

# Study 2
EXPERIMENTS_DB=data/study2.db Rscript scripts/run_experiment.R config2.yaml
```

### Option 3: Wrapper Script

```bash
#!/bin/bash
# run_study.sh
STUDY=$1
EXPERIMENTS_DB=data/${STUDY}_experiments.db Rscript scripts/run_experiment.R configs/${STUDY}.yaml

# Usage:
# ./run_study.sh pilot
# ./run_study.sh full_study
```

---

## Summary

**Default**: `data/experiments.db` ✅ (better than root!)

**Configure**: Edit `.db_config` file

**Priority**: 
1. Environment variable (temporary)
2. .db_config file (persistent)
3. Default (fallback)

**Verify**: `source("R/db_config.R"); print_db_config()`

**Backup**: Manual copies or automated scripts

**Security**: Never commit, encrypt if sensitive

---

**Questions?** See:
- `data/README.md` - Data directory info
- `R/db_config.R` - Configuration code
- `.db_config` - Your configuration file

---

**Last Updated**: October 3, 2025  
**Your feedback**: Database now in proper `data/` directory, not root!
