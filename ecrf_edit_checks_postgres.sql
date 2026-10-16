
-- =====================================================================
-- Hypertension Treatment eCRF: practice project (PostgreSQL)
-- Synthetic public dataset (Kaggle, CC BY 4.0). Not a real trial.
-- Run the parts in order: PART 1 -> 2 -> 3 -> 4 -> 5.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1: RAW TABLE (a deliberately loose landing table)
-- Everything is TEXT and there are no CHECK constraints, on purpose.
-- A real EDC accepts the entry and then raises a query, so bad values
-- must be able to load and be caught by the edit checks, not rejected
-- on import. Import your CSV into this table (see the steps in chat).
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS crf;
DROP TABLE IF EXISTS ecrf_raw;

CREATE TABLE ecrf_raw (
    row_id            SERIAL PRIMARY KEY,   -- added by us, not in the CSV
    patient_id        TEXT,
    site_id           TEXT,
    age               TEXT,
    gender            TEXT,
    enrollment_date   TEXT,
    treatment_group   TEXT,
    adverse_events    TEXT,
    dropout           TEXT,
    systolic_bp       TEXT,
    diastolic_bp      TEXT,
    cholesterol_level TEXT
);

-- Two small helper functions. PostgreSQL stops with an error if you
-- cast bad text to a number or date, so these return NULL instead and
-- let the edit checks (not an import error) deal with the problem.
CREATE OR REPLACE FUNCTION to_num(t TEXT) RETURNS NUMERIC AS $$
    SELECT CASE WHEN btrim(t) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(t)::NUMERIC END;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION to_date_safe(t TEXT) RETURNS DATE AS $$
BEGIN
    RETURN NULLIF(btrim(t), '')::DATE;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ---------------------------------------------------------------------
-- PART 2: IMPORT CSV, THEN PROFILE THE DATA
-- Look at the data BEFORE trusting any range.
-- ---------------------------------------------------------------------

-- 2a. Row count
SELECT COUNT(*) AS total_rows FROM ecrf_raw;

-- 2b. Min / max of each numeric column
SELECT
  MIN(to_num(age))               AS min_age,  MAX(to_num(age))               AS max_age,
  MIN(to_num(site_id))           AS min_site, MAX(to_num(site_id))           AS max_site,
  MIN(to_num(systolic_bp))       AS min_sys,  MAX(to_num(systolic_bp))       AS max_sys,
  MIN(to_num(diastolic_bp))      AS min_dia,  MAX(to_num(diastolic_bp))      AS max_dia,
  MIN(to_num(cholesterol_level)) AS min_chol, MAX(to_num(cholesterol_level)) AS max_chol,
  MIN(to_num(adverse_events))    AS min_ae,   MAX(to_num(adverse_events))    AS max_ae
FROM ecrf_raw;

-- 2c. Blank / missing counts per column
SELECT
  COUNT(*) FILTER (WHERE NULLIF(btrim(patient_id),'')      IS NULL) AS blank_patient_id,
  COUNT(*) FILTER (WHERE NULLIF(btrim(age),'')             IS NULL) AS blank_age,
  COUNT(*) FILTER (WHERE NULLIF(btrim(gender),'')          IS NULL) AS blank_gender,
  COUNT(*) FILTER (WHERE NULLIF(btrim(enrollment_date),'') IS NULL) AS blank_enrol_date,
  COUNT(*) FILTER (WHERE NULLIF(btrim(systolic_bp),'')     IS NULL) AS blank_sys,
  COUNT(*) FILTER (WHERE NULLIF(btrim(diastolic_bp),'')    IS NULL) AS blank_dia
FROM ecrf_raw;

-- 2d. The exact spellings of the coded fields. Check these against the
--     allowed values in EC006 and EC011 below and adjust if needed.
SELECT treatment_group, COUNT(*) FROM ecrf_raw GROUP BY treatment_group ORDER BY 1;
SELECT gender,          COUNT(*) FROM ecrf_raw GROUP BY gender          ORDER BY 1;
SELECT dropout,         COUNT(*) FROM ecrf_raw GROUP BY dropout         ORDER BY 1;

-- 2e. How many participants are under 18? (your README finding)
SELECT COUNT(*) AS under_18 FROM ecrf_raw WHERE to_num(age) < 18;

-- 2f. A few raw dates, to confirm the format (expected YYYY-MM-DD)
SELECT enrollment_date FROM ecrf_raw LIMIT 5;

-- ---------------------------------------------------------------------
-- PART 3: VIEW. Same data with blanks turned into NULL and text turned
-- into numbers/dates, so the edit checks stay short and readable.
-- ---------------------------------------------------------------------
CREATE VIEW crf AS
SELECT
  row_id,
  NULLIF(btrim(patient_id),'')            AS subjid,
  to_num(site_id)                         AS siteid,
  to_num(age)                             AS age,
  NULLIF(btrim(gender),'')                AS sex,
  NULLIF(btrim(enrollment_date),'')       AS enrldt_txt,   -- as typed
  to_date_safe(enrollment_date)           AS enrldt,       -- as a real date (NULL if invalid)
  treatment_group                         AS trtgrp,       -- untrimmed on purpose, so stray spaces are caught
  to_num(adverse_events)                  AS aecount,
  NULLIF(btrim(dropout),'')               AS dropout,
  to_num(systolic_bp)                     AS sysbp,
  to_num(diastolic_bp)                    AS diabp,
  to_num(cholesterol_level)               AS chol
FROM ecrf_raw;

-- ---------------------------------------------------------------------
-- PART 4: THE 11 EDIT CHECKS (one query each; matches Edit Checks tab)
-- Each returns the rows that should raise a query. Zero rows = clean.
-- ---------------------------------------------------------------------

-- EC001 Duplicate Subject ID (Hard)
SELECT 'EC001' AS check_id, subjid, COUNT(*) AS n_records,
       'Duplicate Subject ID.' AS message
FROM crf WHERE subjid IS NOT NULL
GROUP BY subjid HAVING COUNT(*) > 1;

-- EC002 Required fields missing: AGE, SEX, ENRLDT (Hard)
SELECT 'EC002' AS check_id, row_id, subjid,
       'Required field missing.' AS message
FROM crf WHERE age IS NULL OR sex IS NULL OR enrldt_txt IS NULL;

-- EC003 Age outside 18-90 (Query)
SELECT 'EC003' AS check_id, row_id, subjid, age,
       'Age outside of range. Verify.' AS message
FROM crf WHERE age IS NOT NULL AND (age < 18 OR age > 90);

-- EC004 Site ID outside 1-50 (Hard)
SELECT 'EC004' AS check_id, row_id, subjid, siteid,
       'Invalid Site ID.' AS message
FROM crf WHERE siteid IS NOT NULL AND (siteid < 1 OR siteid > 50);

-- EC005 Enrolment date in the future or not a valid date (Query)
SELECT 'EC005' AS check_id, row_id, subjid, enrldt_txt,
       'Enrollment date is in the future or not a valid date.' AS message
FROM crf WHERE enrldt_txt IS NOT NULL AND (enrldt IS NULL OR enrldt > CURRENT_DATE);

-- EC006 Treatment group not one of the allowed values (Hard)
-- EDIT THE LIST to match what query 2d showed you.
SELECT 'EC006' AS check_id, row_id, subjid, trtgrp,
       'Invalid treatment group.' AS message
FROM crf WHERE trtgrp IS NULL
   OR trtgrp NOT IN ('Placebo','Drug A','Drug B');

-- EC007 Systolic BP outside 70-250 (Query)
SELECT 'EC007' AS check_id, row_id, subjid, sysbp,
       'SYSBP outside expected range. Verify.' AS message
FROM crf WHERE sysbp IS NOT NULL AND (sysbp < 70 OR sysbp > 250);

-- EC008 Diastolic not lower than systolic (Query)
SELECT 'EC008' AS check_id, row_id, subjid, sysbp, diabp,
       'DIABP is not lower than SYSBP.' AS message
FROM crf WHERE sysbp IS NOT NULL AND diabp IS NOT NULL AND diabp >= sysbp;

-- EC009 Cholesterol outside 100-400 (Query)
SELECT 'EC009' AS check_id, row_id, subjid, chol,
       'Cholesterol outside expected range.' AS message
FROM crf WHERE chol IS NOT NULL AND (chol < 100 OR chol > 400);

-- EC010 AE count must be a whole number, 0 or more (Query)
SELECT 'EC010' AS check_id, row_id, subjid, aecount,
       'Invalid AE count.' AS message
FROM crf WHERE aecount IS NOT NULL AND (aecount < 0 OR aecount <> trunc(aecount));

-- EC011 Dropout must be 0 or 1 (Hard)
SELECT 'EC011' AS check_id, row_id, subjid, dropout,
       'Dropout must be 0 or 1.' AS message
FROM crf WHERE dropout IS NULL OR dropout NOT IN ('0','1');

-- ---------------------------------------------------------------------
-- PART 5: SUMMARY. One row per check with the number of queries raised.
-- Paste these counts into validation log.
-- ---------------------------------------------------------------------
SELECT 'EC001' AS check_id, COUNT(*) AS queries
  FROM (SELECT subjid FROM crf WHERE subjid IS NOT NULL GROUP BY subjid HAVING COUNT(*) > 1) d
UNION ALL SELECT 'EC002', COUNT(*) FROM crf WHERE age IS NULL OR sex IS NULL OR enrldt_txt IS NULL
UNION ALL SELECT 'EC003', COUNT(*) FROM crf WHERE age IS NOT NULL AND (age < 18 OR age > 90)
UNION ALL SELECT 'EC004', COUNT(*) FROM crf WHERE siteid IS NOT NULL AND (siteid < 1 OR siteid > 50)
UNION ALL SELECT 'EC005', COUNT(*) FROM crf WHERE enrldt_txt IS NOT NULL AND (enrldt IS NULL OR enrldt > CURRENT_DATE)
UNION ALL SELECT 'EC006', COUNT(*) FROM crf WHERE trtgrp IS NULL OR trtgrp NOT IN ('Placebo','Drug A','Drug B')
UNION ALL SELECT 'EC007', COUNT(*) FROM crf WHERE sysbp IS NOT NULL AND (sysbp < 70 OR sysbp > 250)
UNION ALL SELECT 'EC008', COUNT(*) FROM crf WHERE sysbp IS NOT NULL AND diabp IS NOT NULL AND diabp >= sysbp
UNION ALL SELECT 'EC009', COUNT(*) FROM crf WHERE chol IS NOT NULL AND (chol < 100 OR chol > 400)
UNION ALL SELECT 'EC010', COUNT(*) FROM crf WHERE aecount IS NOT NULL AND (aecount < 0 OR aecount <> trunc(aecount))
UNION ALL SELECT 'EC011', COUNT(*) FROM crf WHERE dropout IS NULL OR dropout NOT IN ('0','1');