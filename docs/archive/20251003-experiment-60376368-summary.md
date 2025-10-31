# Experiment Summary: Test GPT-OSS-120B New Prompt

**Date**: 2025-10-03
**Experiment ID**: `60376368-2f1b-4b08-81a9-2f0ea815cd21`
**Author**: Xiaosong
**Config**: `configs/experiments/exp_002_gpt_oss_20251003.yaml`

## Objective

Test new simplified prompt (v0.2.1_April) focused on explicit abuse type definitions for IPV detection in suicide narratives.

## Configuration

### Model Settings
- **Model**: `mlx-community/gpt-oss-120b`
- **Provider**: MLX (local)
- **API**: `http://localhost:1234/v1/chat/completions`
- **Temperature**: 0.2
- **Seed**: 1024

### Prompt Design

**System Prompt** (v0.2.1_April):
- Starts with `/think hard!` instruction
- Defines IPV scope: abuse by current/former intimate partner, boyfriend, girlfriend, spouse, ex, or father of victim's children
- Explicitly excludes: friends, peers, strangers, non-intimate family members
- Lists 6 abuse categories with specific examples:
  1. Physical (hitting, choking, strangulation, etc.)
  2. Sexual (rape, coercion, exploitation, etc.)
  3. Psychological (threats, stalking, intimidation, etc.)
  4. Emotional (gaslighting, isolation, humiliation, etc.)
  5. Economic (financial control, restricting work/school, etc.)
  6. Legal (threats involving police, courts, agencies, etc.)

**User Template**:
- Task: Determine IPV presence (true/false)
- Mark TRUE if: abuse by intimate partner OR victim in women's shelter
- Assign confidence (0.00-1.00)
- Return JSON: `{detected, confidence, rationale}`

### Data
- **Source**: `data-raw/suicide_IPV_manuallyflagged.xlsx`
- **Total narratives**: 404
- **Manual IPV labels**: 48 positive (11.9%), 356 negative (88.1%)

## Results

### Execution Summary
- **Status**: ✅ Completed
- **Duration**: 26.5 minutes (1,590 seconds)
- **Processing speed**: 3.9 sec/narrative
- **Narratives processed**: 404/404 (100%)
- **Errors**: 0

### Detection Performance

| Metric | Value |
|--------|-------|
| **Accuracy** | **94.1%** |
| **Precision (IPV)** | 76.1% |
| **Recall (IPV)** | 72.9% |
| **F1 Score** | 74.5% |
| **Average Confidence** | 0.88 |

### Confusion Matrix

|  | Predicted: IPV | Predicted: No IPV |
|--|----------------|-------------------|
| **Actual: IPV** | 35 (TP) | 13 (FN) |
| **Actual: No IPV** | 11 (FP) | 345 (TN) |

- **True Positives**: 35 (correctly identified IPV)
- **True Negatives**: 345 (correctly rejected non-IPV)
- **False Positives**: 11 (wrongly flagged as IPV)
- **False Negatives**: 13 (missed IPV cases)

### Detection Distribution
- **LLM detected IPV**: 46 cases (11.4%)
- **Manual flagged IPV**: 48 cases (11.9%)
- **Detection rate alignment**: Very close to ground truth

## Key Findings

### Strengths
1. **High accuracy** (94.1%) with good generalization
2. **High confidence scores** (avg 0.88) - model is decisive
3. **Balanced precision/recall** (76%/73%) - no extreme bias
4. **Fast processing** - 3.9 sec/narrative
5. **Zero errors** - robust execution

### Weaknesses
1. **13 false negatives** (27% of actual IPV cases missed)
2. **11 false positives** (24% of detected IPV incorrect)

## Error Analysis

### False Negatives (Missed IPV - High Confidence)
Examples where model was very confident but WRONG:

| Incident | Type | Conf | Rationale |
|----------|------|------|-----------|
| 339093 | CME | 0.97 | "No information about intimate partner, abuse, or shelter" |
| 322959 | CME | 0.96 | "No evidence of abuse by intimate partner or shelter" |
| 326605 | CME | 0.96 | "No abusive behavior by intimate partner described" |

**Pattern**: Missing IPV when narratives lack explicit abuse descriptions. Model requires clear evidence and doesn't infer from context.

### False Positives (Wrong IPV Detection - High Confidence)
Examples where model detected IPV but manual review said NO:

| Incident | Type | Conf | Rationale |
|----------|------|------|-----------|
| 339436 | LE | 0.98 | "Girlfriend committed severe physical abuse (stabbing and genital mutilation)" |
| 323074 | LE | 0.95 | "Ex-partner sent threatening messages after miscarriage" |
| 324475 | CME | 0.95 | "Husband used choke hold during argument" |

**Pattern**: Detecting genuine abuse patterns but possibly:
- Victim was perpetrator, not victim of IPV (role confusion)
- Context suggests mutual violence or different circumstances
- Manual flags may have different interpretation criteria

## Comparison to Baseline (Exp cc5ab818)

| Metric | Baseline | New Prompt | Change |
|--------|----------|------------|--------|
| Test size | 10 | 404 | +394 |
| Accuracy | 100% | 94.1% | -5.9% |
| Avg Confidence | ~0.22 | 0.88 | +0.66 |
| Runtime/narrative | 6.1s | 3.9s | -36% faster |

**Observations**:
- New prompt produces **much higher confidence** (0.22 → 0.88)
- **Faster processing** despite similar model
- Larger test reveals real-world accuracy (~94%)

## Conclusions

1. **Prompt v0.2.1_April performs well** for IPV detection with 94% accuracy
2. **Explicit abuse definitions help** - model confidently applies categories
3. **Main failure mode**: Missing implicit/contextual IPV cues (requires explicit mentions)
4. **Processing speed acceptable** for production use (3.9s/narrative)
5. **Consider**: Adding contextual inference rules or multi-step reasoning for edge cases

## Next Steps

1. **Review false negatives**: Identify common missing patterns
2. **Audit false positives**: Check if manual labels need refinement
3. **Prompt iteration**: Add contextual reasoning for subtle IPV indicators
4. **Scale testing**: Run on full NVDRS dataset
5. **Compare models**: Test same prompt with different LLMs

## Database Location

- **Experiments DB**: `data/experiments.db`
- **Results table**: `narrative_results` (404 rows for this experiment)
- **CSV export**: `benchmark_results/experiment_60376368-2f1b-4b08-81a9-2f0ea815cd21_*.csv`
- **JSON export**: `benchmark_results/experiment_60376368-2f1b-4b08-81a9-2f0ea815cd21_*.json`
