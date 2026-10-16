-- =====================================================================
-- eCRF edit check VALIDATION (PostgreSQL)
-- Proves each edit check fires when it should, using a COPY of the data
-- with deliberate errors planted. The original table is never changed.
-- Run AFTER ecrf_edit_checks_postgres.sql (needs ecrf_raw and view crf).
-- Safe to re-run: it rebuilds the copy from scratch each time.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1: Make the test copy (source data stays untouched)
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS crf_test;
DROP TABLE IF EXISTS ecrf_test;
CREATE TABLE ecrf_test AS SELECT * FROM ecrf_raw;
ALTER TABLE ecrf_test ADD PRIMARY KEY (row_id);

-- Same view as "crf", but over the test copy
CREATE VIEW crf_test AS
SELECT
  row_id,
  NULLIF(btrim(patient_id),'')            AS subjid,
  to_num(site_id)                         AS siteid,
  to_num(age)                             AS age,
  NULLIF(btrim(gender),'')                AS sex,
  NULLIF(btrim(enrollment_date),'')       AS enrldt_txt,
  to_date_safe(enrollment_date)           AS enrldt,
  treatment_group                         AS trtgrp,
  to_num(adverse_events)                  AS aecount,
  NULLIF(btrim(dropout),'')               AS dropout,
  to_num(systolic_bp)                     AS sysbp,
  to_num(diastolic_bp)                    AS diabp,
  to_num(cholesterol_level)               AS chol
FROM ecrf_test;

-- ---------------------------------------------------------------------
-- STEP 2: Plant 20 deliberate errors (rows 1-20 of the COPY only)
-- ---------------------------------------------------------------------
-- EC001 duplicate ID: row 1 gets row 2's ID                (2 rows flagged)
UPDATE ecrf_test SET patient_id = (SELECT patient_id FROM ecrf_test WHERE row_id = 2) WHERE row_id = 1;
-- EC002 missing required fields
UPDATE ecrf_test SET gender = ''            WHERE row_id = 3;
UPDATE ecrf_test SET age = NULL             WHERE row_id = 4;
-- EC003 age out of range (too young, too old)
UPDATE ecrf_test SET age = '7'              WHERE row_id = 5;
UPDATE ecrf_test SET age = '95'             WHERE row_id = 6;
-- EC004 invalid site
UPDATE ecrf_test SET site_id = '75'         WHERE row_id = 7;
-- EC005 future date; impossible date
UPDATE ecrf_test SET enrollment_date = '1/1/31'  WHERE row_id = 8;
UPDATE ecrf_test SET enrollment_date = '2/30/22' WHERE row_id = 9;
-- EC006 bad treatment group (typo; trailing space)
UPDATE ecrf_test SET treatment_group = 'Drg A'    WHERE row_id = 10;
UPDATE ecrf_test SET treatment_group = 'Placebo ' WHERE row_id = 11;
-- EC007 systolic out of range
UPDATE ecrf_test SET systolic_bp = '300'    WHERE row_id = 12;
-- EC008 diastolic higher than systolic; diastolic equal to systolic
UPDATE ecrf_test SET diastolic_bp = (to_num(systolic_bp) + 10)::INT::TEXT WHERE row_id = 14;
UPDATE ecrf_test SET diastolic_bp = systolic_bp                         WHERE row_id = 15;
-- EC009 cholesterol out of range
UPDATE ecrf_test SET cholesterol_level = '20' WHERE row_id = 16;
-- EC010 negative AE count; non-whole AE count
UPDATE ecrf_test SET adverse_events = '-2'  WHERE row_id = 17;
UPDATE ecrf_test SET adverse_events = '1.5' WHERE row_id = 18;
-- EC011 dropout not 0/1; dropout blank
UPDATE ecrf_test SET dropout = '2'          WHERE row_id = 19;
UPDATE ecrf_test SET dropout = ''           WHERE row_id = 20;

-- What was changed (for your README): original value vs planted value
SELECT o.row_id, 'patient_id' AS field, o.patient_id AS original, t.patient_id AS planted
  FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.patient_id IS DISTINCT FROM t.patient_id
UNION ALL SELECT o.row_id,'gender',o.gender,t.gender FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.gender IS DISTINCT FROM t.gender
UNION ALL SELECT o.row_id,'age',o.age,t.age FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.age IS DISTINCT FROM t.age
UNION ALL SELECT o.row_id,'site_id',o.site_id,t.site_id FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.site_id IS DISTINCT FROM t.site_id
UNION ALL SELECT o.row_id,'enrollment_date',o.enrollment_date,t.enrollment_date FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.enrollment_date IS DISTINCT FROM t.enrollment_date
UNION ALL SELECT o.row_id,'treatment_group',o.treatment_group,t.treatment_group FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.treatment_group IS DISTINCT FROM t.treatment_group
UNION ALL SELECT o.row_id,'systolic_bp',o.systolic_bp,t.systolic_bp FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.systolic_bp IS DISTINCT FROM t.systolic_bp
UNION ALL SELECT o.row_id,'diastolic_bp',o.diastolic_bp,t.diastolic_bp FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.diastolic_bp IS DISTINCT FROM t.diastolic_bp
UNION ALL SELECT o.row_id,'cholesterol_level',o.cholesterol_level,t.cholesterol_level FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.cholesterol_level IS DISTINCT FROM t.cholesterol_level
UNION ALL SELECT o.row_id,'adverse_events',o.adverse_events,t.adverse_events FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.adverse_events IS DISTINCT FROM t.adverse_events
UNION ALL SELECT o.row_id,'dropout',o.dropout,t.dropout FROM ecrf_raw o JOIN ecrf_test t USING (row_id) WHERE o.dropout IS DISTINCT FROM t.dropout
ORDER BY row_id, field;

-- ---------------------------------------------------------------------
-- STEP 3: VALIDATION RESULT (this is your validation log)
-- For each check: how many rows it flagged on the original data, how
-- many on the test copy, and whether the INCREASE equals the number of
-- errors planted. Using the increase means the 31 queries already in
-- the original data do not confuse the result.
-- PASS = it caught every planted error and flagged nothing extra.
-- ---------------------------------------------------------------------
WITH allrows AS (
  SELECT 'orig'::TEXT AS src, c.*, COUNT(*) OVER (PARTITION BY subjid) AS dup_n FROM crf c
  UNION ALL
  SELECT 'test',               t.*, COUNT(*) OVER (PARTITION BY subjid) FROM crf_test t
),
hits AS (
  SELECT src, 'EC001' AS check_id, row_id FROM allrows WHERE subjid IS NOT NULL AND dup_n > 1
  UNION ALL SELECT src,'EC002',row_id FROM allrows WHERE age IS NULL OR sex IS NULL OR enrldt_txt IS NULL
  UNION ALL SELECT src,'EC003',row_id FROM allrows WHERE age IS NOT NULL AND (age < 18 OR age > 90)
  UNION ALL SELECT src,'EC004',row_id FROM allrows WHERE siteid IS NOT NULL AND (siteid < 1 OR siteid > 50)
  UNION ALL SELECT src,'EC005',row_id FROM allrows WHERE enrldt_txt IS NOT NULL AND (enrldt IS NULL OR enrldt > CURRENT_DATE)
  UNION ALL SELECT src,'EC006',row_id FROM allrows WHERE trtgrp IS NULL OR trtgrp NOT IN ('Placebo','Drug A','Drug B')
  UNION ALL SELECT src,'EC007',row_id FROM allrows WHERE sysbp IS NOT NULL AND (sysbp < 70 OR sysbp > 250)
  UNION ALL SELECT src,'EC008',row_id FROM allrows WHERE sysbp IS NOT NULL AND diabp IS NOT NULL AND diabp >= sysbp
  UNION ALL SELECT src,'EC009',row_id FROM allrows WHERE chol IS NOT NULL AND (chol < 100 OR chol > 400)
  UNION ALL SELECT src,'EC010',row_id FROM allrows WHERE aecount IS NOT NULL AND (aecount < 0 OR aecount <> trunc(aecount))
  UNION ALL SELECT src,'EC011',row_id FROM allrows WHERE dropout IS NULL OR dropout NOT IN ('0','1')
),
planted(check_id, what_was_planted, expected_extra) AS (
  VALUES
  ('EC001','Row 1 given the same Patient_ID as row 2 (both rows flagged)', 2),
  ('EC002','Blank Gender (row 3); blank Age (row 4)', 2),
  ('EC003','Age 7 (row 5); age 95 (row 6)', 2),
  ('EC004','Site_ID 75 (row 7)', 1),
  ('EC005','Future date 1/1/31 (row 8); impossible date 2/30/22 (row 9)', 2),
  ('EC006','"Drg A" (row 10); "Placebo " with trailing space (row 11)', 2),
  ('EC007','Systolic BP 300 (row 12)', 1),
  ('EC008','Diastolic 10 above systolic (row 14); diastolic equal to systolic (row 15)', 2),
  ('EC009','Cholesterol 20 (row 16)', 1),
  ('EC010','AE count -2 (row 17); AE count 1.5 (row 18)', 2),
  ('EC011','Dropout 2 (row 19); blank dropout (row 20)', 2)
),
counts AS (
  SELECT check_id,
         COUNT(*) FILTER (WHERE src = 'orig') AS flagged_original,
         COUNT(*) FILTER (WHERE src = 'test') AS flagged_test_copy
  FROM hits GROUP BY check_id
)
SELECT p.check_id,
       p.what_was_planted,
       p.expected_extra                              AS expected_increase,
       COALESCE(c.flagged_original, 0)               AS flagged_original,
       COALESCE(c.flagged_test_copy, 0)              AS flagged_test_copy,
       COALESCE(c.flagged_test_copy, 0) - COALESCE(c.flagged_original, 0) AS actual_increase,
       CASE WHEN COALESCE(c.flagged_test_copy, 0) - COALESCE(c.flagged_original, 0) = p.expected_extra
            THEN 'PASS' ELSE 'FAIL' END              AS result
FROM planted p LEFT JOIN counts c USING (check_id)
ORDER BY p.check_id;