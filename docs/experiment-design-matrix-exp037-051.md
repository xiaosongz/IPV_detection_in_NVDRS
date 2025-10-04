# Experiment Design Matrix: exp_037-051

**Date**: 2025-10-03
**Author**: gemini

## Objective

To test the hypothesis that providing a more explicit JSON structure and examples in the prompt will reduce JSON parsing errors and improve the reliability of the LLM's output. This batch of experiments replicates `exp_007-021` with a new set of prompt versions (`v0.4.x`).

## Key Change: Improved JSON Prompting

The `user_template` for all prompts in this batch was updated to include a more robust description of the desired JSON output. 

**Old Format:**
```json
{
  "detected": true/false,
  "confidence": 0.00-1.00,
  "rationale": "200 char fact-based explanation"
}
```

**New Format (v0.4.x):**
```json
{
  "detected": <boolean>,          // true or false
  "confidence": <number>,          // decimal 0.0 to 1.0, e.g., 0.85
  "rationale": <string>            // max 200 characters
}
```
This new format also includes valid and invalid examples to guide the model.

## Experiment Matrix

| New Exp ID | Replicates | Prompt Strategy (Version) | Temperature | Reasoning |
|:-----------|:-----------|:--------------------------|:------------|:----------|
| **exp_037**| exp_007    | Baseline (`v0.4.1`)       | 0.0         | Medium    |
| **exp_038**| exp_008    | Baseline (`v0.4.1`)       | 0.0         | High      |
| **exp_039**| exp_009    | Baseline (`v0.4.1`)       | 0.2         | High      |
| **exp_040**| exp_010    | Indirect Indicators (`v0.4.2`) | 0.0 | Medium    |
| **exp_041**| exp_011    | Indirect Indicators (`v0.4.2`) | 0.0 | High      |
| **exp_042**| exp_012    | Indirect Indicators (`v0.4.2`) | 0.2 | High      |
| **exp_043**| exp_013    | Strict Criteria (`v0.4.3`)     | 0.0 | Medium    |
| **exp_044**| exp_014    | Strict Criteria (`v0.4.3`)     | 0.0 | High      |
| **exp_045**| exp_015    | Strict Criteria (`v0.4.3`)     | 0.2 | High      |
| **exp_046**| exp_016    | Full Context (`v0.4.4`)        | 0.0 | Medium    |
| **exp_047**| exp_017    | Full Context (`v0.4.4`)        | 0.0 | High      |
| **exp_048**| exp_018    | Full Context (`v0.4.4`)        | 0.2 | High      |
| **exp_049**| exp_019    | Chain of Thought (`v0.4.5`)    | 0.0 | Medium    |
| **exp_050**| exp_020    | Chain of Thought (`v0.4.5`)    | 0.0 | High      |
| **exp_051**| exp_021    | Chain of Thought (`v0.4.5`)    | 0.2 | High      |

## Hypothesis & Success Metrics

- **Primary Hypothesis**: The improved JSON formatting will significantly reduce the number of JSON parsing errors.
- **Success Metric**: A >75% reduction in parsing errors when comparing a new experiment (e.g., `exp_042`) with its original counterpart (`exp_012`).
- **Secondary Metric**: Core performance metrics (Accuracy, Recall) should remain stable or improve slightly.
