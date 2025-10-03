# Data Directory

This directory contains the experiment tracking database and related data files.

---

## Files

### experiments.db
**Purpose**: Main SQLite database for experiment tracking  
**Schema**: 3 tables (experiments, narrative_results, source_narratives)  
**Size**: ~700 KB  
**Created**: Automatically on first run

**Do not commit**: Added to .gitignore

---

## Configuration

Database location is configured in `.db_config` file in project root.

**Default**:
```
EXPERIMENTS_DB=data/experiments.db
```

**To change**:
1. Edit `.db_config` in project root
2. Set `EXPERIMENTS_DB=your/path/here.db`
3. Restart any running scripts

---

## Directory Structure

```
data/
├── README.md              # This file
├── experiments.db         # Main database (gitignored)
└── backups/               # Optional: Manual backups
```

---

## Backup Recommendations

The database contains valuable experiment results. Consider:

1. **Manual backups** before major changes:
   ```bash
   cp data/experiments.db data/backups/experiments_$(date +%Y%m%d).db
   ```

2. **Version control** (use git-lfs for large files):
   ```bash
   git lfs track "data/backups/*.db"
   ```

3. **Cloud sync** (Dropbox, Google Drive, etc.):
   - Symlink data/ to cloud storage
   - Or use automatic sync tools

---

## Database Size Management

- **Current**: ~700 KB
- **Growth rate**: ~50 KB per experiment (10 narratives)
- **Expected**: ~7 MB for 100 experiments
- **Cleanup**: Query and export old experiments, then delete from DB

```sql
-- Export old experiments
sqlite3 data/experiments.db "
  SELECT * FROM experiments 
  WHERE created_at < date('now', '-6 months')
" > old_experiments.csv

-- Delete after confirming export
sqlite3 data/experiments.db "
  DELETE FROM narrative_results 
  WHERE experiment_id IN (
    SELECT experiment_id FROM experiments 
    WHERE created_at < date('now', '-6 months')
  )
"
```

---

## Security Note

This database may contain sensitive information (narrative text, PII indicators).

- ✅ Added to .gitignore (not committed to git)
- ⚠️ Ensure backup location is secure
- ⚠️ Consider encryption for backups
- ⚠️ Follow your institution's data policies

---

**Last Updated**: October 3, 2025
