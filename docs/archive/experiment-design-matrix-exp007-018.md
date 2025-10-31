# Experiment Design Matrix: exp_007 - exp_018

**Date**: 2025-10-03
**Purpose**: Systematic testing of prompt strategies, temperature, and reasoning levels to optimize IPV detection accuracy

## Design Overview

Testing **4 prompt strategies** × **3 configurations** = **12 experiments**

### Prompt Strategy Evolution (v0.3.1 → v0.3.4)

| Version | Strategy | Key Features | Hypothesis |
|---------|----------|--------------|------------|
| **v0.3.1** | Baseline + Victim Check | Adds victim role validation to prevent perpetrator confusion | Fix false positives from homicide/perpetrator cases |
| **v0.3.2** | Indirect Indicators | Adds shelter, police intervention, restraining orders as strong signals | Fix false negatives from sparse CME reports |
| **v0.3.3** | Strict Criteria | Adds self-defense detection and mutual combat exclusion | Reduce false positives from defensive violence |
| **v0.3.4** | Full Context | Combines all improvements: victim role + indicators + self-defense | Best overall performance |

### Configuration Matrix

| Config | Temperature | Reasoning | Rationale |
|--------|-------------|-----------|-----------|
| **A** | 0.0 | medium | Deterministic, balanced reasoning |
| **B** | 0.0 | high | Deterministic, deep analysis |
| **C** | 0.2 | high | Slightly random, deep analysis |

## Experiment Grid

| Exp | Prompt Version | Strategy | Temp | Reasoning | Config File |
|-----|---------------|----------|------|-----------|-------------|
| **007** | v0.3.1 | Baseline + Victim Check | 0.0 | medium | exp_007_baseline_t00_medium.yaml |
| **008** | v0.3.1 | Baseline + Victim Check | 0.0 | high | exp_008_baseline_t00_high.yaml |
| **009** | v0.3.1 | Baseline + Victim Check | 0.2 | high | exp_009_baseline_t02_high.yaml |
| **010** | v0.3.2 | Indirect Indicators | 0.0 | medium | exp_010_indicators_t00_medium.yaml |
| **011** | v0.3.2 | Indirect Indicators | 0.0 | high | exp_011_indicators_t00_high.yaml |
| **012** | v0.3.2 | Indirect Indicators | 0.2 | high | exp_012_indicators_t02_high.yaml |
| **013** | v0.3.3 | Strict Criteria + Self-Defense | 0.0 | medium | exp_013_strict_t00_medium.yaml |
| **014** | v0.3.3 | Strict Criteria + Self-Defense | 0.0 | high | exp_014_strict_t00_high.yaml |
| **015** | v0.3.3 | Strict Criteria + Self-Defense | 0.2 | high | exp_015_strict_t02_high.yaml |
| **016** | v0.3.4 | Full Context (All Features) | 0.0 | medium | exp_016_context_t00_medium.yaml |
| **017** | v0.3.4 | Full Context (All Features) | 0.0 | high | exp_017_context_t00_high.yaml |
| **018** | v0.3.4 | Full Context (All Features) | 0.2 | high | exp_018_context_t02_high.yaml |

## Prompt Strategy Details

### v0.3.1: Baseline + Victim Check

**Key Addition**:
```
CRITICAL VICTIM ROLE CHECK:
- The deceased must be the VICTIM of IPV (not the perpetrator)
- Suicide after being IPV victim = IPV ✓
- Suicide after committing violence against partner = NOT IPV ✗
- Homicide victim (killed by partner, then partner suicide) = NOT IPV ✗
```

**Target Error Pattern**:
- Incident 339436: Girlfriend killed boyfriend → NOT IPV (he's homicide victim)
- Incident 324475: Deceased attacked husband, he restrained her → May be self-defense

### v0.3.2: Indirect Indicators

**Key Addition**:
```
INDIRECT IPV INDICATORS (Strong Evidence):
- Women's shelter stay (e.g., Family Violence Project) → AUTOMATIC IPV
- Police separation/intervention in partner relationship → HIGH IPV probability
- Restraining order against partner → HIGH IPV probability
- "Domestic issues" or "domestic violence" mentioned → Likely IPV
- Partner arrested for DV → HIGH IPV probability
```

**Target Error Pattern**:
- Incident 322959: CME missed IPV, but LE had "women's shelter" + "domestic issues"
- Incident 326605: CME missed IPV, but LE had "police separated them" + "V reported hit by boyfriend"

### v0.3.3: Strict Criteria + Self-Defense

**Key Addition**:
```
STRICT EXCLUSION CRITERIA (NOT IPV):
- Deceased initiated violence AND partner restrained/defended = Self-defense, NOT IPV
- Mutual combat (both violent, no clear victim) = NOT IPV
- Deceased was perpetrator, not victim = NOT IPV
- Homicide victim (not suicide) = NOT IPV for this study
- Single argument without abuse pattern = NOT IPV
```

**Target Error Pattern**:
- Incident 324475: "V assaulted husband... husband put her in choke hold" → Self-defense, NOT IPV
- Mutual violence scenarios where both are aggressors

### v0.3.4: Full Context (Combined)

**Combines ALL features**:
1. Victim role validation (v0.3.1)
2. Indirect indicators (v0.3.2)
3. Self-defense detection (v0.3.3)
4. Strict evidence requirements

**Expected**: Best overall performance - highest accuracy, balanced precision/recall

## Expected Outcomes

### Temperature Impact
- **0.0 (deterministic)**: More consistent, potentially more conservative
- **0.2 (slight randomness)**: May help with edge cases, slight variability

### Reasoning Level Impact
- **medium**: Faster processing (~2-3s/narrative), good for clear cases
- **high**: Slower processing (~4-5s/narrative), better for complex/ambiguous cases

### Hypothesis Testing

| Hypothesis | Test | Expected Result |
|------------|------|-----------------|
| H1: Victim role check reduces false positives | Compare v0.3.1 vs v0.2.1 | Lower FP rate, maintain recall |
| H2: Indirect indicators improve recall | Compare v0.3.2 vs v0.3.1 | Higher recall, maintain precision |
| H3: Self-defense detection reduces false positives | Compare v0.3.3 vs v0.3.1 | Lower FP rate, especially mutual combat cases |
| H4: Full context gives best overall performance | Compare v0.3.4 vs all others | Highest accuracy, best F1 score |
| H5: High reasoning improves accuracy | Compare high vs medium | Higher accuracy, slower speed |
| H6: Temperature=0.0 is optimal for classification | Compare 0.0 vs 0.2 | More consistent results at 0.0 |

## Baseline Comparison

| Metric | exp_002 (v0.2.1) | Target for exp_007-018 |
|--------|------------------|------------------------|
| Accuracy | 94.1% | **>95%** |
| Precision | 76.1% | **>80%** |
| Recall | 72.9% | **>75%** |
| F1 Score | 74.5% | **>77%** |
| False Positives | 11 | **<10** |
| False Negatives | 13 | **<12** |
| Speed | 3.9s/narr | 3-5s/narr (acceptable) |

## Running the Experiments

### Sequential Execution
```r
# Run all 12 experiments
configs <- paste0("exp_", sprintf("%03d", 7:18), "_*.yaml")
for (config in configs) {
  run_experiment(config)
}
```

### Check Progress
```bash
sqlite3 data/experiments.db "SELECT experiment_id, experiment_name, status, accuracy FROM experiments WHERE experiment_id LIKE 'exp_0%' ORDER BY created_at;"
```

## Analysis Plan

After completion:

1. **Performance Comparison**: Compare all 12 on accuracy, precision, recall, F1
2. **Error Analysis**: Identify which strategy best handles specific error types
3. **Speed vs Accuracy**: Plot reasoning level impact on performance
4. **Temperature Impact**: Analyze consistency (variance) between runs
5. **Best Model Selection**: Identify optimal prompt + config for production

## Files Created

All experiment configs are in: `configs/experiments/`
- `exp_007_baseline_t00_medium.yaml`
- `exp_008_baseline_t00_high.yaml`
- `exp_009_baseline_t02_high.yaml`
- `exp_010_indicators_t00_medium.yaml`
- `exp_011_indicators_t00_high.yaml`
- `exp_012_indicators_t02_high.yaml`
- `exp_013_strict_t00_medium.yaml`
- `exp_014_strict_t00_high.yaml`
- `exp_015_strict_t02_high.yaml`
- `exp_016_context_t00_medium.yaml`
- `exp_017_context_t00_high.yaml`
- `exp_018_context_t02_high.yaml`
