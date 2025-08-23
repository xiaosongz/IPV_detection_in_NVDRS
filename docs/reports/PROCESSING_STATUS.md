# IPV Detection - Processing ALL 289 Cases

## Current Status: 🔄 RUNNING

### Dataset Information
- **Source**: `nvdrsipvdetector/inst/extdata/sui_all_flagged.xlsx`
- **Total Cases**: 289
- **Columns**: IncidentID, NarrativeLE, NarrativeCME, ipv_flag_LE, ipv_flag_CME
- **LE Narratives Available**: 245/289 (84.8%)
- **CME Narratives Available**: 287/289 (99.3%)

### Processing Configuration
- **Threshold**: 0.595 (optimized from testing)
- **Weights**: LE=0.4, CME=0.6
- **Model**: openai/gpt-oss-120b
- **API Endpoint**: http://192.168.10.22:1234/v1

### Processing Details
- **Start Time**: 2025-08-23 13:23:07
- **Estimated Duration**: ~29 minutes
- **Estimated Completion**: ~13:52
- **Processing Rate**: ~10 cases per minute
- **API Calls**: 578 total (2 per case)

### What's Happening
1. Each case has its LE and CME narratives analyzed separately
2. LLM identifies IPV indicators in each narrative
3. Confidence scores are calculated for each
4. Results are combined using weighted average
5. Final prediction made using optimal threshold of 0.595
6. Results saved every 50 cases as checkpoint

### Expected Outputs
- Full results CSV with all predictions and confidence scores
- Performance metrics (accuracy, precision, recall, F1)
- Comparison with ground truth labels
- Indicator frequency analysis
- Confidence score distributions

### Intermediate Checkpoints
- Every 50 cases: Results saved to `tests/test_results/all_289_intermediate.csv`
- Every 10 cases: Progress update with ETA

### Why This Matters
This is a comprehensive test on a much larger dataset (289 vs 20 cases), providing:
- More robust performance validation
- Better understanding of edge cases
- Statistical significance for metrics
- Real-world performance assessment

### Next Steps After Completion
1. Analyze performance metrics on full dataset
2. Identify any systematic errors or patterns
3. Compare with smaller test set results
4. Generate comprehensive report
5. Make final recommendations for production deployment

---
*Processing in progress... Please wait for completion.*