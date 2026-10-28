-- =====================================================================
-- CASE STUDY DEMO: MIDDLEWARE OVER DIFFERENT DATABASES
-- (the diagram in your notebook: Schema Mapping, Query Translation,
--  Data Conversion, Source Selection, Result Integration -> Integrated view)
--
-- Story: the salon grows. Downtown now runs an OLD system (names like
-- APPT_NO, dates written as '28-OCT-2026', price in paise). Campus Road
-- runs a NEWER app (names like id, ISO dates, price in rupees).
-- Each keeps its own database. The middleware makes them look like ONE.
-- Here the two "sources" are just two tables with different shapes.
-- =====================================================================
USE stylist_salon;
DROP VIEW  IF EXISTS integrated_appointments;
DROP VIEW  IF EXISTS map_source_campus;
DROP VIEW  IF EXISTS map_source_downtown;
DROP TABLE IF EXISTS src_campus_app;
DROP TABLE IF EXISTS src_downtown_legacy;

-- SOURCE 1: old Downtown system (different names, text dates, paise)
CREATE TABLE src_downtown_legacy (
  APPT_NO   INT,
  CUST_NAME VARCHAR(40),
  APPT_DT   VARCHAR(11),          -- '28-OCT-2026'
  SLOT_TXT  VARCHAR(5),
  AMT_PAISE INT                   -- 80000 = Rs 800
);
INSERT INTO src_downtown_legacy VALUES
  (101, 'Riya',  '28-OCT-2026', '11:00', 30000),
  (102, 'Dev',   '29-OCT-2026', '12:00', 80000);

-- SOURCE 2: newer Campus Road app (different names, ISO dates, rupees)
CREATE TABLE src_campus_app (
  id          INT,
  customer    VARCHAR(40),
  starts_at   DATETIME,           -- 2026-10-29 12:00:00
  price_rs    DECIMAL(8,2)
);
INSERT INTO src_campus_app VALUES
  (7, 'Arjun', '2026-10-29 12:00:00', 800.00),
  (8, 'Neel',  '2026-10-30 15:00:00', 450.00);

-- 1) SCHEMA MAPPING + 3) DATA CONVERSION: each source is mapped to one common shape
CREATE VIEW map_source_downtown AS
  SELECT 'Downtown'                              AS branch,
         CONCAT('D-', APPT_NO)                   AS appt_ref,     -- mapping:  APPT_NO   -> appt_ref
         CUST_NAME                               AS customer,     -- mapping:  CUST_NAME -> customer
         STR_TO_DATE(APPT_DT, '%d-%b-%Y')        AS appt_date,    -- conversion: text date -> DATE
         SLOT_TXT                                AS slot,
         AMT_PAISE / 100                         AS total_rs      -- conversion: paise -> rupees
  FROM src_downtown_legacy;

CREATE VIEW map_source_campus AS
  SELECT 'Campus Road'                           AS branch,
         CONCAT('C-', id)                        AS appt_ref,     -- mapping:  id        -> appt_ref
         customer                                AS customer,
         DATE(starts_at)                         AS appt_date,    -- conversion: DATETIME -> DATE
         TIME_FORMAT(starts_at, '%H:%i')         AS slot,         -- conversion: DATETIME -> 'HH:MM'
         price_rs                                AS total_rs
  FROM src_campus_app;

-- 5) RESULT INTEGRATION: results from all sources are merged = the INTEGRATED VIEW
CREATE VIEW integrated_appointments AS
  SELECT * FROM map_source_downtown
  UNION ALL
  SELECT * FROM map_source_campus;

SELECT '--- Integrated view: one table, even though the sources are different ---' AS step;
SELECT * FROM integrated_appointments ORDER BY appt_date, slot;

-- 2) QUERY TRANSLATION + 4) SOURCE SELECTION
-- The user asks ONE global question. The middleware picks which sources are
-- needed and rewrites the question in each source's own language.
SELECT '--- Global question: revenue on 2026-10-29 at ALL branches ---' AS step;
SELECT SUM(total_rs) AS revenue FROM integrated_appointments WHERE appt_date = '2026-10-29';

SELECT '--- What the middleware really sends (translated per source) ---' AS step;
-- to Downtown (old system, text dates, paise):
SELECT SUM(AMT_PAISE) / 100 AS downtown_part FROM src_downtown_legacy WHERE APPT_DT = '29-OCT-2026';
-- to Campus Road (new system, DATETIME, rupees):
SELECT SUM(price_rs) AS campus_part FROM src_campus_app WHERE DATE(starts_at) = '2026-10-29';

-- SOURCE SELECTION: a question about Campus Road only never touches Downtown
SELECT '--- Source selection: only Campus Road is asked ---' AS step;
SELECT * FROM map_source_campus WHERE customer = 'Arjun';
