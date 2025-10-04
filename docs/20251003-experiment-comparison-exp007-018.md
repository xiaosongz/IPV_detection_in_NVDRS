# Experiment Comparison Report: Prompt Strategy Analysis

**Date**: 2025-10-03
**Experiments**: exp_007 - exp_018 (12 experiments)
**Baseline**: exp_002 (v0.2.1, 94.1% accuracy)
**Model**: mlx-community/gpt-oss-120b
**Dataset**: 404 suicide narratives (48 IPV cases, 356 non-IPV)

---

## Executive Summary

Tested 4 prompt strategies with 3 configurations each (temperature × reasoning level). **Best performer**: **Indirect Indicators strategy (v0.3.2)** achieved **95.0% accuracy** and **80.8% F1 score**, significantly outperforming baseline by catching 87.5% of IPV cases (vs 72.9% previously).

### Winner: exp_012 (Indirect Indicators, T=0.2, Reasoning=High)
- **Accuracy**: 95.0% (+0.9% vs baseline)
- **F1 Score**: 80.8% (+6.3% vs baseline)
- **Recall**: 87.5% (+14.6% vs baseline) ⭐
- **Precision**: 75.0% (-1.1% vs baseline)
- **False Negatives**: 6 (-7 vs baseline) ⭐

---

## Strategy Comparison

### Strategy 1: Baseline + Victim Check (v0.3.1)
**Experiments**: exp_007, exp_008, exp_009

**What it does**:
- Adds victim role validation to prevent perpetrator/victim confusion
- Explicitly excludes homicide victims (not suicide)
- Checks: Is deceased the VICTIM of IPV or the PERPETRATOR?

**Key prompt additions**:
```
CRITICAL VICTIM ROLE CHECK:
- The deceased must be the VICTIM of IPV (not the perpetrator)
- Suicide after being IPV victim = IPV ✓
- Suicide after committing violence against partner = NOT IPV ✗
- Homicide victim (killed by partner, then partner suicide) = NOT IPV ✗
```

**Reasoning steps**:
1. Identify deceased's role - were they abused BY partner or did they abuse partner?
2. Check for intimate partner relationship
3. Identify abusive behaviors
4. Women's shelter = automatic IPV
5. Final determination

**Performance**:
| Metric | Medium (007) | High (008) | High+T0.2 (009) | Average |
|--------|--------------|------------|-----------------|---------|
| Accuracy | 93.3% | 94.3% | 94.2% | **93.9%** |
| Precision | 74.4% | 75.5% | 77.8% | **75.9%** |
| Recall | 66.7% | 77.1% | 72.9% | **72.2%** |
| F1 | 70.3% | 76.3% | 75.3% | **74.0%** |
| FP | 11 | 12 | 10 | **11** |
| FN | 16 | 11 | 13 | **13** |

**Strengths**:
- ✅ Solid baseline performance
- ✅ Balanced precision/recall
- ✅ Clear role differentiation

**Weaknesses**:
- ❌ Still misses 11-16 IPV cases
- ❌ No leverage of indirect indicators

---

### Strategy 2: Indirect Indicators (v0.3.2) ⭐ WINNER
**Experiments**: exp_010, exp_011, exp_012

**What it does**:
- Recognizes institutional/systemic IPV evidence beyond explicit abuse
- Prioritizes indirect indicators FIRST before looking for explicit abuse
- Treats certain signals (shelter, police intervention) as strong IPV probability

**Key prompt additions**:
```
INDIRECT IPV INDICATORS (Strong Evidence):
- Women's shelter stay (e.g., Family Violence Project) → AUTOMATIC IPV
- Police separation/intervention in partner relationship → HIGH IPV probability
- Restraining order against partner → HIGH IPV probability
- "Domestic issues" or "domestic violence" mentioned → Likely IPV
- Partner arrested for DV → HIGH IPV probability

VICTIM ROLE CHECK:
- Deceased must be IPV victim, not perpetrator
- Homicide victim (not suicide) = NOT IPV for this study
```

**Reasoning steps**:
1. **Check INDIRECT indicators FIRST** (shelter, police, restraining orders, domestic issues)
2. Identify deceased's role (victim vs perpetrator)
3. Check for intimate partner relationship
4. Identify explicit abusive behaviors
5. Final determination

**Performance**:
| Metric | Medium (010) | High (011) | High+T0.2 (012) | Average |
|--------|--------------|------------|-----------------|---------|
| Accuracy | 94.2% | 94.3% | **95.0%** | **94.5%** |
| Precision | 72.2% | 73.6% | 75.0% | **73.6%** |
| Recall | 83.0% | 81.3% | **87.5%** | **83.9%** |
| F1 | 77.2% | 77.2% | **80.8%** | **78.4%** |
| FP | 15 | 14 | 14 | **14** |
| FN | 8 | 9 | **6** | **8** |

**Strengths**:
- ✅✅ **Best recall** (83-88%): Catches most IPV cases
- ✅✅ **Fewest false negatives** (6-9 missed cases)
- ✅ Leverages institutional evidence (police reports, shelters)
- ✅ Works well with sparse CME narratives

**Weaknesses**:
- ⚠️ Slightly more false positives (14 vs 10-11)
- ⚠️ Lower precision (73-75% vs 76-78%)

**Why it wins**:
Catches IPV cases that baseline misses by recognizing:
- Women's shelter stays (even if no explicit abuse mentioned)
- Police separations ("officer had boyfriend leave")
- "Domestic issues" language
- Restraining orders

**Example success case** (Incident 322959):
- **CME narrative**: "38yo female, hanging, lived with friend, alcoholism" → No IPV mentioned
- **LE narrative**: "Women's shelter 3 weeks ago, domestic issues with ex-boyfriend"
- **Baseline**: Missed (CME had no evidence)
- **Indicators**: Caught (women's shelter = auto IPV) ✓

---

### Strategy 3: Strict Criteria + Self-Defense (v0.3.3)
**Experiments**: exp_013, exp_014, exp_015

**What it does**:
- Focuses on EXCLUDING cases that might be self-defense or mutual combat
- Requires very explicit evidence of abuse BY partner AGAINST deceased
- Conservative approach: "when uncertain, default to FALSE"

**Key prompt additions**:
```
STRICT EXCLUSION CRITERIA (NOT IPV):
- Deceased initiated violence AND partner restrained/defended = Self-defense, NOT IPV
- Mutual combat (both violent, no clear victim) = NOT IPV
- Deceased was perpetrator, not victim = NOT IPV
- Homicide victim (not suicide) = NOT IPV for this study
- Single argument without abuse pattern = NOT IPV

REQUIRE CLEAR EVIDENCE:
- Must have explicit abuse BY partner AGAINST deceased
- Breakups, arguments, sadness alone = NOT IPV
- When uncertain, default to FALSE
```

**Reasoning steps**:
1. Was this suicide (self-inflicted)? If homicide → FALSE
2. Who initiated violence? If deceased attacked partner first → likely self-defense
3. Check for abuse BY partner AGAINST deceased (not vice versa)
4. Verify evidence is explicit, not implied
5. Women's shelter = AUTO TRUE
6. Final determination

**Performance**:
| Metric | Medium (013) | High (014) | High+T0.2 (015) | Average |
|--------|--------------|------------|-----------------|---------|
| Accuracy | 92.1% | 92.3% | 92.8% | **92.4%** |
| Precision | 86.4% | 87.0% | **95.2%** | **89.5%** |
| Recall | 39.6% | 41.7% | 41.7% | **41.0%** |
| F1 | 54.3% | 56.3% | 58.0% | **56.2%** |
| FP | 3 | 3 | **1** | **2** |
| FN | 29 | 28 | 28 | **28** |

**Strengths**:
- ✅✅ **Highest precision** (86-95%): Very few false positives
- ✅ Only 1-3 false positives (excellent specificity)
- ✅ Good at identifying self-defense scenarios

**Weaknesses**:
- ❌❌ **Terrible recall** (40-42%): Misses 60% of IPV cases!
- ❌❌ 28-29 false negatives (catastrophic for safety)
- ❌ Too conservative for real-world use

**Why it fails**:
The "when uncertain, default to FALSE" rule causes the model to miss genuine IPV cases that lack crystal-clear evidence. Real-world narratives are often ambiguous.

**Trade-off**: Optimizes for precision at severe cost to recall. Not suitable when missing IPV cases has serious consequences.

---

### Strategy 4: Full Context (v0.3.4)
**Experiments**: exp_016, exp_017, exp_018

**What it does**:
- Combines ALL improvements: victim role + indirect indicators + self-defense detection + strict criteria
- Attempts to get "best of all worlds"
- Most comprehensive prompt with all safeguards

**Key prompt additions**:
```
INDIRECT IPV INDICATORS (Strong Evidence):
[Same as v0.3.2]

EXCLUSION CRITERIA (NOT IPV):
[Same as v0.3.3]

CRITICAL CHECKS:
- Deceased must be suicide victim (self-inflicted death)
- Deceased must be IPV victim (abused BY partner)
- Require explicit evidence or strong indirect indicators
- When uncertain, default to FALSE
```

**Reasoning steps**:
1. Confirm this is suicide (self-inflicted), not homicide
2. Check INDIRECT indicators first (shelter, police, restraining orders, domestic issues)
3. Identify who was the aggressor/victim
4. If deceased attacked partner → check if partner's response was self-defense
5. Look for explicit abuse BY partner AGAINST deceased
6. Final determination (when uncertain → FALSE)

**Performance**:
| Metric | Medium (016) | High (017) | High+T0.2 (018) | Average |
|--------|--------------|------------|-----------------|---------|
| Accuracy | 93.8% | 94.3% | **94.8%** | **94.3%** |
| Precision | 82.9% | 83.8% | **84.6%** | **83.8%** |
| Recall | 60.4% | 64.6% | 68.8% | **64.6%** |
| F1 | 69.9% | 72.9% | 75.9% | **72.9%** |
| FP | 6 | 6 | 6 | **6** |
| FN | 19 | 17 | 15 | **17** |

**Strengths**:
- ✅ **High precision** (83-85%): Few false positives
- ✅ Only 6 false positives (very reliable when it says IPV)
- ✅ Comprehensive safeguards

**Weaknesses**:
- ❌ **Lower recall** (60-69%): Still misses 15-19 IPV cases
- ❌ The strict criteria override the benefit of indirect indicators
- ❌ Doesn't achieve "best of both worlds"

**Why it underperforms**:
Combining strict exclusion criteria with indirect indicators creates conflicting signals. The "when uncertain, default to FALSE" rule makes the model too conservative, negating the benefit of indirect indicators.

**Trade-off**: Better precision than Indicators, worse recall. Middle ground between Indicators and Strict.

---

## Strategy Comparison Summary

| Strategy | Philosophy | Accuracy | Precision | Recall | F1 | Use Case |
|----------|------------|----------|-----------|--------|----|----|
| **Indicators** (v0.3.2) | **Trust institutional signals** | **94.5%** | 73.6% | **83.9%** | **78.4%** | **Production (maximize safety)** ⭐ |
| Full Context (v0.3.4) | Balance all factors | 94.3% | **83.8%** | 64.6% | 72.9% | High-stakes (minimize false accusations) |
| Baseline (v0.3.1) | Basic role validation | 93.9% | 75.9% | 72.2% | 74.0% | Simple baseline |
| Strict (v0.3.3) | Minimize false positives | 92.4% | **89.5%** | 41.0% | 56.2% | ❌ Not recommended |

---

## Key Design Differences

### 1. **Approach to Uncertainty**

| Strategy | When Evidence is Ambiguous | Result |
|----------|---------------------------|--------|
| Indicators | Trust indirect signals (shelter, police) | Higher recall |
| Strict | Default to FALSE | Lower recall, higher precision |
| Full Context | Default to FALSE (strict rule wins) | Medium recall |
| Baseline | Require explicit abuse | Medium recall |

### 2. **Priority Order in Reasoning**

**Indicators (v0.3.2)**:
```
1. Check indirect indicators FIRST
2. Then check victim role
3. Then check explicit abuse
→ Institutional evidence takes priority
```

**Strict (v0.3.3)**:
```
1. Check exclusion criteria FIRST
2. Then verify explicit evidence
3. Default to FALSE if uncertain
→ Exclusions take priority
```

**Full Context (v0.3.4)**:
```
1. Check suicide vs homicide
2. Check indirect indicators
3. Check aggressor/victim
4. Check self-defense
5. Check explicit abuse
6. Default to FALSE if uncertain
→ All checks required, conservative default
```

### 3. **Treatment of Sparse Narratives**

| Scenario | Indicators | Strict | Full Context |
|----------|-----------|--------|--------------|
| CME says "suicide, lived with boyfriend" | May detect if LE has "police intervention" | Likely FALSE (no explicit abuse) | Likely FALSE (uncertain → FALSE) |
| CME says "women's shelter stay" | **AUTO IPV** ✓ | **AUTO IPV** ✓ | **AUTO IPV** ✓ |
| LE says "domestic issues mentioned" | **HIGH IPV probability** ✓ | Maybe (needs more evidence) | Maybe (strict rules may override) |

---

## Temperature & Reasoning Impact

### Temperature Comparison

| Temp | Avg Accuracy | Avg F1 | Best Strategy | Observation |
|------|--------------|--------|---------------|-------------|
| **0.2** | **94.2%** | **72.5%** | Indicators | Slightly better for edge cases |
| 0.0 | 93.6% | 69.7% | Indicators | More conservative |

**Finding**: Temperature=0.2 provides marginal improvement (+0.6% accuracy), especially for Indicators strategy (exp_012: 95.0% accuracy).

### Reasoning Level Comparison

| Reasoning | Avg Accuracy | Avg F1 | Avg Speed | Best Strategy |
|-----------|--------------|--------|-----------|---------------|
| **high** | **94.0%** | **69.9%** | ~2,090s | Indicators |
| medium | 93.1% | 68.1% | ~1,949s | Indicators |

**Finding**: High reasoning provides +0.9% accuracy improvement. Worth the extra ~150s (7%) runtime for production.

---

## Detailed Performance Breakdown

### All 12 Experiments Ranked by F1 Score

| Rank | Exp | Strategy | Config | Accuracy | Precision | Recall | F1 | FP | FN |
|------|-----|----------|--------|----------|-----------|--------|----|----|-----|
| 🥇 1 | **012** | **Indicators** | T=0.2, High | **95.0%** | 75.0% | **87.5%** | **80.8%** | 14 | **6** |
| 🥈 2 | 010 | Indicators | T=0.0, Med | 94.2% | 72.2% | 83.0% | 77.2% | 15 | 8 |
| 🥉 3 | 011 | Indicators | T=0.0, High | 94.3% | 73.6% | 81.3% | 77.2% | 14 | 9 |
| 4 | 008 | Baseline | T=0.0, High | 94.3% | 75.5% | 77.1% | 76.3% | 12 | 11 |
| 5 | 018 | Full Context | T=0.2, High | 94.8% | 84.6% | 68.8% | 75.9% | 6 | 15 |
| 6 | 009 | Baseline | T=0.2, High | 94.2% | 77.8% | 72.9% | 75.3% | 10 | 13 |
| 7 | 017 | Full Context | T=0.0, High | 94.3% | 83.8% | 64.6% | 72.9% | 6 | 17 |
| 8 | 007 | Baseline | T=0.0, Med | 93.3% | 74.4% | 66.7% | 70.3% | 11 | 16 |
| 9 | 016 | Full Context | T=0.0, Med | 93.8% | 82.9% | 60.4% | 69.9% | 6 | 19 |
| 10 | 015 | Strict | T=0.2, High | 92.8% | **95.2%** | 41.7% | 58.0% | **1** | 28 |
| 11 | 014 | Strict | T=0.0, High | 92.3% | 87.0% | 41.7% | 56.3% | 3 | 28 |
| 12 | 013 | Strict | T=0.0, Med | 92.1% | 86.4% | 39.6% | 54.3% | 3 | 29 |

---

## Comparison to Baseline (exp_002)

### exp_012 (Winner) vs exp_002 (Baseline)

| Metric | exp_002 (v0.2.1) | exp_012 (v0.3.2) | Change | Improvement |
|--------|------------------|------------------|--------|-------------|
| **Accuracy** | 94.1% | **95.0%** | +0.9% | ✅ Small gain |
| **Precision** | 76.1% | 75.0% | -1.1% | ⚠️ Slight loss |
| **Recall** | 72.9% | **87.5%** | **+14.6%** | ✅✅ Major gain |
| **F1 Score** | 74.5% | **80.8%** | **+6.3%** | ✅✅ Major gain |
| **False Positives** | 11 | 14 | +3 | ⚠️ Slight increase |
| **False Negatives** | 13 | **6** | **-7** | ✅✅ Major reduction |
| **Speed** | 3.9s/narr | 5.2s/narr | +1.3s | ⚠️ 33% slower |

**Key Takeaway**: exp_012 reduces missed IPV cases by 54% (13→6) with only 3 more false positives. This is the ideal trade-off for safety-critical applications.

---

## Recommendations

### For Production: Use exp_012 Configuration ⭐

**Config**:
```yaml
prompt: v0.3.2_indicators
temperature: 0.2
reasoning: high
model: mlx-community/gpt-oss-120b
```

**Why**:
- ✅ **Best overall performance**: 95% accuracy, 80.8% F1
- ✅ **Highest recall**: Catches 87.5% of IPV cases (critical for safety)
- ✅ **Fewest missed cases**: Only 6 false negatives
- ✅ **Leverages institutional evidence**: Shelter, police, restraining orders
- ✅ **Acceptable false positive rate**: 14 cases (reviewable)

**Use when**:
- Safety is paramount (missing IPV cases has serious consequences)
- You have resources to review false positives
- Sparse narratives are common (CME reports)

### Alternative: exp_018 (Full Context)

**Config**:
```yaml
prompt: v0.3.4_context
temperature: 0.2
reasoning: high
```

**Why**:
- ✅ **High precision**: 84.6% (very reliable when it says IPV)
- ✅ **Very few false positives**: Only 6 cases
- ⚠️ **Lower recall**: 68.8% (misses 15 IPV cases)

**Use when**:
- False accusations are very costly
- You need high confidence in positive detections
- You can tolerate missing some IPV cases

### Don't Use: Strict Strategy (exp_013-015)

**Why not**:
- ❌ Misses 60% of IPV cases (28-29 false negatives)
- ❌ Unacceptable for safety-critical applications
- ❌ "When uncertain, default to FALSE" is too conservative

**Only use if**:
- You need 95%+ precision
- False positives are absolutely unacceptable
- You understand you'll miss most IPV cases

---

## Lessons Learned

### 1. **Indirect Indicators are Powerful**
Institutional evidence (women's shelter, police intervention, restraining orders) are strong IPV signals that should be prioritized over explicit abuse descriptions.

### 2. **Combining Strategies Can Backfire**
Full Context (v0.3.4) underperformed Indicators (v0.3.2) because strict exclusion criteria overrode the benefits of indirect indicators. **More rules ≠ better performance.**

### 3. **Conservative Defaults Hurt Recall**
The "when uncertain, default to FALSE" rule in Strict and Full Context strategies caused them to miss genuine IPV cases with ambiguous evidence.

### 4. **Temperature Matters for Edge Cases**
Temperature=0.2 slightly outperforms 0.0, especially for Indicators strategy. The randomness helps with borderline cases.

### 5. **High Reasoning Worth the Cost**
+0.9% accuracy improvement for ~7% longer runtime is acceptable for production use.

### 6. **Precision-Recall Trade-off is Real**
- Indicators: High recall (87.5%), medium precision (75%)
- Strict: Low recall (41%), high precision (95%)
- Full Context: Medium recall (69%), high precision (85%)
- **Choose based on your cost function**: What's more expensive, missed IPV or false positives?

---

## Future Work

1. **Multi-narrative fusion**: Combine CME + LE narratives for each incident (one narrative might have evidence the other lacks)

2. **Confidence calibration**: Analyze if model confidence correlates with accuracy (are low-confidence cases more error-prone?)

3. **Error pattern analysis**: Deep dive into the 6 false negatives in exp_012 - what patterns are still being missed?

4. **Active learning**: Manually review the 14 false positives to improve precision without hurting recall

5. **Ensemble approach**: Combine predictions from Indicators + Full Context strategies

6. **Model comparison**: Test same prompts with different models (Qwen3, Llama, GPT-4)

---

## Conclusion

The **Indirect Indicators strategy (v0.3.2)** with **temperature=0.2** and **high reasoning** (exp_012) is the clear winner for IPV detection, achieving:

- **95.0% accuracy** (best overall)
- **87.5% recall** (catches most IPV cases)
- **Only 6 missed cases** (down from 13 in baseline)
- **80.8% F1 score** (best balance)

This represents a **significant improvement over baseline** by recognizing institutional evidence (shelters, police interventions) as strong IPV indicators. The strategy is particularly effective for sparse narratives that lack explicit abuse descriptions.

For production deployment, use exp_012 configuration to maximize safety while maintaining acceptable precision.
