# Data Directory

This directory contains processed data files. Raw input data should be placed in the `data-raw/` directory.

## File Structure

- Raw data files: Place in `../data-raw/`
- Processed data files: Store here after cleaning/transformation
- Intermediate results: Can be stored here for multi-step analyses

## Data Format

Expected input format for IPV detection:
- `incident_id`: Unique identifier for each case
- `narrativecme`: Medical examiner narrative text
- `narrativele`: Law enforcement narrative text
- Additional columns are preserved but not used in analysis

## Privacy Note

Ensure all data files comply with privacy and confidentiality requirements. Do not commit sensitive or personally identifiable information to version control.