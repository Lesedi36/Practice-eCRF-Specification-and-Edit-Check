# Practice-eCRF-Specification-and-Edit-Check (Hypertention Treatment)
A practice project: a mock eCRF specification and a set of SQL edit checks (PostgreSQL), run and validated on a public synthetic clinical trial dataset.

**This is a learning project. It is not a real trial, not built in a commercial EDC system, and not GCP-validated.**

## Data

- **Dataset:** Hypertension Treatment Clinical Trial Dataset (Kaggle) — https://www.kaggle.com/datasets/isabelladil/phase-iii-clinical-trial-dataset/data
- **Licence:** CC BY 4.0
- **Size:** 1,000 records, one row per participant
- **Nature:** synthetic. No real patient data.
- The original data is never modified. Test errors are added to a separate copy.

## What is in this repository

| File | Purpose |
|---|---|
| `eCRF_Spec.xlsx` | Study overview, 5 forms, 11 field definitions, 11 edit checks (with severity) and the validation log |
| `ecrf_edit_checks_postgres.sql` | Raw landing table, data profiling, a cleaned view, and the 11 edit-check queries |
| `ecrf_validation_postgres.sql` | Builds a copy of the data, plants 20 deliberate errors, and reports PASS/FAIL for each check |

## Method

1. **Specification.** Mapped the dataset's 11 columns to five forms (Demographics, Treatment assignment, Vital signs, Adverse events, Disposition), with data type, units, required status and allowed values for each field.
2. **Edit check specification.** Wrote 11 checks covering duplicates, missing values, ranges, date logic, coded values and a cross-field consistency check (diastolic must be lower than systolic). Each is marked Hard (invalid or missing) or Query (please verify).
3. **Profiling first.** Looked at row counts, min/max values, blanks and exact spellings before setting any rule.
4. **Programming.** Loaded the data into a deliberately loose text table (so bad values load and are caught by the checks, as in an EDC), then wrote one SQL query per check.
5. **Validation.** Copied the data, planted 20 errors, and confirmed each check flags exactly the errors planted and nothing extra.

## Findings on the source data

The 11 checks raised **31 queries** on the original 1,000 records:

| Check | Queries | Detail |
|---|---|---|
| EC003 Age outside 18-90 | 16 | 12 under 18, 4 over 90 |
| EC008 Diastolic not lower than systolic | 14 | 9 with diastolic above systolic, 5 with equal values |
| EC009 Cholesterol outside 100-400 mg/dL | 1 | |
| All other checks | 0 | |

These are queries for review, not confirmed errors. The allowed ranges are my own assumptions for an adult trial, not protocol-defined. Because the dataset is synthetic, the flagged rows most likely reflect how it was generated.

## Validation result

All 11 checks passed: each caught every planted error and flagged nothing extra. The full table is in `eCRF_Spec.xlsx` (Validation Log tab).

## Limitations

- One row per participant: no visits, so no visit-date logic or repeating forms.
- The adverse events field is a count only, with no event details.
- Ranges are assumed. In a real study they come from the protocol.
- Written in plain SQL, not in an EDC system such as Medidata Rave.
- No audit trail, query management or user access controls.

## How to run

1. Create a PostgreSQL database.
2. Run Part 1 of `ecrf_edit_checks_postgres.sql`, import the CSV into `ecrf_raw` (leave out `row_id`), then run Parts 2 to 5.
3. Run `ecrf_validation_postgres.sql` and read the final table.

Dates in the source data are written month/day/year with a two-digit year (for example `1/1/22`). The date function in Part 1 assumes this.

## Acknowledgement

Dataset: Hypertension Treatment Clinical Trial Dataset, Kaggle, licensed CC BY 4.0.
