-- =====================================================================================
-- FIT5137 S2 2026 - Assignment 2 - MonCity self-driving car data warehouse
-- FINAL SCRIPT (Oracle SQL; run top-to-bottom in your own schema, source = MonCity)
--
--   00  Reset (re-runnable)
--   01  C2 Exploration of the operational database (OPDB)
--   01A C2 BEFORE evidence  - detection SQL for errors E1-E6
--   01B C2 Cleaning         - corrections applied to local copies (*_C) only
--   01C C2 AFTER evidence   - verification SQL for errors E1-E6
--   02  C4 Version-1 (highest aggregation) implementation, with PK/FK/CHECK constraints
--   03  Validation          - row counts, control totals, bridge-weight check
--   04  C3 analytical questions answered from Version-1
--   05  C5 analysis queries  - reproduce every figure in the C5 findings report
--   06  C4 screenshot queries - table structure (DESC) and contents
--
-- Control totals after cleaning (all later sections reconcile to these):
--   bookings 10,000 | maintenance 1,000 records / A$302,700 |
--   accident records 1,000 car-accident involvements over 992 distinct accidents
-- =====================================================================================


-- =====================================================================================
-- 00 / RESET - drop previous versions so the script can be re-run from the top.
--      PURGE frees the space immediately (avoids ORA-01536 quota errors).
-- =====================================================================================
BEGIN
    FOR t IN (SELECT table_name
              FROM   user_tables
              WHERE  table_name IN ('BOOKINGFACT', 'MAINTENANCEFACT', 'ACCIDENTFACT',
                                    'TEMPFACT_BOOKING', 'TEAMCENTERBRIDGE', 'TEAMDIM',
                                    'RESEARCHCENTERDIM', 'MAINTENANCETYPEDIM', 'CARDIM',
                                    'CARBODYDIM', 'FACULTYDIM', 'MONTHDIM', 'AGEGROUPDIM',
                                    'ERRORDIM', 'ACCIDENTZONEDIM', 'SEVERITYDIM',
                                    'BOOKING_C', 'ACCIDENTINFO_C', 'MAINTENANCE_C',
                                    'PASSENGER_C', 'ERROR_C'))
    LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/


-- =====================================================================================
-- 01 / C2 EXPLORATION - size and key integrity of every OPDB table
-- =====================================================================================
SELECT 'FACULTY' AS table_name, COUNT(*) AS row_count, COUNT(DISTINCT FACULTYID) AS distinct_keys FROM MonCity.FACULTY
UNION ALL SELECT 'RESEARCHCENTER',  COUNT(*), COUNT(DISTINCT CENTERID)        FROM MonCity.RESEARCHCENTER
UNION ALL SELECT 'PASSENGER',       COUNT(*), COUNT(DISTINCT PASSENGERID)     FROM MonCity.PASSENGER
UNION ALL SELECT 'ERROR',           COUNT(*), COUNT(DISTINCT ERRORCODE)       FROM MonCity.ERROR
UNION ALL SELECT 'MAINTENANCETYPE', COUNT(*), COUNT(DISTINCT MAINTENANCETYPE) FROM MonCity.MAINTENANCETYPE
UNION ALL SELECT 'BOOKING',         COUNT(*), COUNT(DISTINCT BOOKINGID)       FROM MonCity.BOOKING
UNION ALL SELECT 'CAR',             COUNT(*), COUNT(DISTINCT REGISTRATIONNO)  FROM MonCity.CAR
UNION ALL SELECT 'MAINTENANCE',     COUNT(*), COUNT(DISTINCT MAINTENANCEID)   FROM MonCity.MAINTENANCE
UNION ALL SELECT 'ACCIDENTINFO',    COUNT(*), COUNT(DISTINCT ACCIDENTID)      FROM MonCity.ACCIDENTINFO
UNION ALL SELECT 'CARACCIDENT',     COUNT(*), COUNT(DISTINCT ACCIDENTID)      FROM MonCity.CARACCIDENT
UNION ALL SELECT 'MAINTENANCETEAM', COUNT(*), COUNT(DISTINCT TEAMID)          FROM MonCity.MAINTENANCETEAM
UNION ALL SELECT 'BELONGTO',        COUNT(*), COUNT(DISTINCT TEAMID)          FROM MonCity.BELONGTO;
-- Read: BOOKING 10,001 rows / 10,000 IDs (E1); ACCIDENTINFO 994 rows / 993 IDs (E3: one NULL ID);
--       CARACCIDENT 1,000 rows / 992 accidents (8 accidents legitimately involve two cars).


-- =====================================================================================
-- 01A / C2 BEFORE EVIDENCE - one detection query (plus supporting context) per error.
--       Each error is justified as: WHY it is an error / WAREHOUSE IMPACT / WHY this fix.
-- =====================================================================================

-- E1 / DUPLICATION - BOOKING T1218 is stored twice, identical in every attribute.
--   Why:    two rows share the primary key and every other value -> one booking, two copies.
--   Impact: NUM_OF_BOOKINGS would count 10,001 and inflate one month/faculty/age/body cell.
--   Fix:    keep one copy (SELECT DISTINCT); nothing valid is lost.
SELECT b.*
FROM   MonCity.BOOKING b
WHERE  b.BOOKINGID IN (SELECT BOOKINGID
                       FROM   MonCity.BOOKING
                       GROUP  BY BOOKINGID
                       HAVING COUNT(*) > 1)
ORDER  BY b.BOOKINGID;

SELECT COUNT(*) AS source_rows, COUNT(DISTINCT BOOKINGID) AS booking_ids
FROM   MonCity.BOOKING;

-- E2 / RELATIONSHIP - accident A2000 cites Error010, which does not exist in ERROR,
--      and A2000 is linked to no car in CARACCIDENT.
--   Why:    orphan foreign key (no parent error code) and no car association.
--   Impact: cannot map to ErrorDim, and cannot be loaded at AccidentFact's per-car grain.
--   Fix:    exclude from the staging copy; no error category or car is invented.
SELECT a.*
FROM   MonCity.ACCIDENTINFO a
WHERE  NOT EXISTS (SELECT 1 FROM MonCity.ERROR e WHERE e.ERRORCODE = a.ERRORCODE);

SELECT COUNT(*) AS car_links_for_a2000
FROM   MonCity.CARACCIDENT
WHERE  ACCIDENTID = 'A2000';

-- E3 / NULL VALUE - one accident has a NULL primary key.
--   Why:    an accident without an identifier cannot be referenced by CARACCIDENT.
--   Impact: no car can be attributed, so it cannot enter AccidentFact; PK would fail.
--   Fix:    exclude from the staging copy (its zone/severity/error detail is lost - acknowledged).
SELECT *
FROM   MonCity.ACCIDENTINFO
WHERE  ACCIDENTID IS NULL;

-- E4 / INCORRECT VALUE concealing a DUPLICATE - M2000 has an impossible -A$200 cost.
--   Why:    every other job carries one positive price per type (M002 = A$200). M2000 matches
--           M936 on car, date, type and team with the opposite sign, no other maintenance
--           event is recorded twice, and its ID lies outside the ID sequence
--           -> M2000 is a sign-reversed re-entry of M936, not a second job.
--   Impact: loaded as-is it adds a phantom record and nets M936's cost to zero; sign-corrected
--           it counts the same A$200 sensor job twice (double counting in MaintenanceFact,
--           Mini Bus cost per booking and centre CE01's weighted cost).
--   Fix:    delete M2000 and keep M936, so the event is counted exactly once.
SELECT MAINTENANCETYPE, MAINTENANCECOST, COUNT(*) AS records
FROM   MonCity.MAINTENANCE
GROUP  BY MAINTENANCETYPE, MAINTENANCECOST
ORDER  BY MAINTENANCETYPE, MAINTENANCECOST;

SELECT m.*
FROM   MonCity.MAINTENANCE m
WHERE  EXISTS (SELECT 1
               FROM   MonCity.MAINTENANCE n
               WHERE  n.MAINTENANCECOST <= 0
               AND    n.REGISTRATIONNO   = m.REGISTRATIONNO
               AND    n.MAINTENANCEDATE  = m.MAINTENANCEDATE
               AND    n.MAINTENANCETYPE  = m.MAINTENANCETYPE
               AND    n.TEAMID           = m.TEAMID)
ORDER  BY m.MAINTENANCEID;

SELECT REGISTRATIONNO, MAINTENANCEDATE, MAINTENANCETYPE, TEAMID, COUNT(*) AS copies
FROM   MonCity.MAINTENANCE
GROUP  BY REGISTRATIONNO, MAINTENANCEDATE, MAINTENANCETYPE, TEAMID
HAVING COUNT(*) > 1;

SELECT MAX(CASE WHEN MAINTENANCEID <> 'M2000'
                THEN CAST(SUBSTR(MAINTENANCEID, 2) AS NUMBER) END) AS highest_other_id_no,
       COUNT(*)                                                    AS source_rows
FROM   MonCity.MAINTENANCE;

-- E5 / INVALID DOMAIN VALUE - passenger U163 belongs to faculty 'Alienware'.
--   Why:    'Alienware' is not a faculty and has no parent row in FACULTY.
--   Impact: any booking by U163 would carry an invalid faculty into BookingFact.
--   Fix:    exclude U163 - the true faculty cannot be derived from any attribute and
--           U163 has no bookings, so no fact is lost (passenger master detail is).
SELECT p.*
FROM   MonCity.PASSENGER p
WHERE  NOT EXISTS (SELECT 1 FROM MonCity.FACULTY f WHERE f.FACULTYID = p.FACULTYID);

SELECT COUNT(*) AS bookings_by_u163
FROM   MonCity.BOOKING
WHERE  PASSENGERID = 'U163';

-- E6 / INCONSISTENT VALUES - misspelt error descriptions ('systeem', 'Unknow') and a
--      missing separator ('failed:Unable') in the ERROR master data.
--   Why:    the labels break the spelling/format used by the other codes.
--   Impact: ErrorDim labels appear verbatim in reports and Power BI; text search and
--           slicers for 'Unknown' or 'Lidar system' miss them. Counts are unaffected.
--   Fix:    targeted REPLACE of the three defects; codes (keys) untouched.
SELECT ERRORCODE, ERRORMESSAGE
FROM   MonCity.ERROR
WHERE  REGEXP_LIKE(ERRORMESSAGE, 'systeem|Unknow[^n]|:[^ ]');


-- =====================================================================================
-- 01B / C2 CLEANING - corrections applied to local copies only (MonCity is read-only).
-- =====================================================================================

-- E1: remove the exact copy. A same-ID row with conflicting values would survive DISTINCT
--     and then fail the primary key, so nothing can be merged silently.
CREATE TABLE BOOKING_C AS
SELECT DISTINCT * FROM MonCity.BOOKING;

ALTER TABLE BOOKING_C ADD CONSTRAINT pk_booking_c PRIMARY KEY (BOOKINGID);

-- E2 / E3: exclude only the two unusable accident rows (neither has a car link).
CREATE TABLE ACCIDENTINFO_C AS
SELECT * FROM MonCity.ACCIDENTINFO;

DELETE FROM ACCIDENTINFO_C WHERE ACCIDENTID = 'A2000' AND ERRORCODE = 'Error010';
DELETE FROM ACCIDENTINFO_C WHERE ACCIDENTID IS NULL;
COMMIT;

ALTER TABLE ACCIDENTINFO_C ADD CONSTRAINT pk_accidentinfo_c PRIMARY KEY (ACCIDENTID);

-- E4: delete the sign-reversed re-entry only when its positive twin exists.
CREATE TABLE MAINTENANCE_C AS
SELECT * FROM MonCity.MAINTENANCE;

DELETE FROM MAINTENANCE_C m
WHERE  m.MAINTENANCEID   = 'M2000'
AND    m.MAINTENANCECOST < 0
AND    EXISTS (SELECT 1
               FROM   MAINTENANCE_C k
               WHERE  k.MAINTENANCEID  <> m.MAINTENANCEID
               AND    k.REGISTRATIONNO  = m.REGISTRATIONNO
               AND    k.MAINTENANCEDATE = m.MAINTENANCEDATE
               AND    k.MAINTENANCETYPE = m.MAINTENANCETYPE
               AND    k.TEAMID          = m.TEAMID
               AND    k.MAINTENANCECOST = -m.MAINTENANCECOST);
COMMIT;

ALTER TABLE MAINTENANCE_C ADD CONSTRAINT pk_maintenance_c PRIMARY KEY (MAINTENANCEID);
ALTER TABLE MAINTENANCE_C ADD CONSTRAINT ck_maintenance_c_cost CHECK (MAINTENANCECOST > 0);

-- E5: exclude the passenger with an invalid faculty (0 bookings -> fact-loss-free).
CREATE TABLE PASSENGER_C AS
SELECT * FROM MonCity.PASSENGER;

DELETE FROM PASSENGER_C WHERE PASSENGERID = 'U163' AND FACULTYID = 'Alienware';
COMMIT;

ALTER TABLE PASSENGER_C ADD CONSTRAINT pk_passenger_c PRIMARY KEY (PASSENGERID);

-- E6: standardise the error descriptions.
CREATE TABLE ERROR_C AS
SELECT * FROM MonCity.ERROR;

UPDATE ERROR_C
SET    ERRORMESSAGE = REPLACE(REPLACE(ERRORMESSAGE, 'systeem', 'system'),
                              'failed:Unable', 'failed: Unable')
WHERE  ERRORCODE = 'Error004';

UPDATE ERROR_C
SET    ERRORMESSAGE = REPLACE(ERRORMESSAGE, 'Unknow issue', 'Unknown issue')
WHERE  ERRORCODE = 'Error005';
COMMIT;

ALTER TABLE ERROR_C ADD CONSTRAINT pk_error_c PRIMARY KEY (ERRORCODE);


-- =====================================================================================
-- 01C / C2 AFTER EVIDENCE - rerun the detection logic on the cleaned copies.
-- =====================================================================================

-- E1: no duplicated booking remains; T1218 appears once; 10,000 bookings.
SELECT BOOKINGID, COUNT(*) AS copies
FROM   BOOKING_C
GROUP  BY BOOKINGID
HAVING COUNT(*) > 1;

SELECT * FROM BOOKING_C WHERE BOOKINGID = 'T1218';

SELECT COUNT(*) AS cleaned_bookings FROM BOOKING_C;

-- E2: no orphan error code remains.
SELECT a.*
FROM   ACCIDENTINFO_C a
WHERE  NOT EXISTS (SELECT 1 FROM MonCity.ERROR e WHERE e.ERRORCODE = a.ERRORCODE);

-- E3: no NULL identifier remains, and no cleaned accident lacks a car link.
SELECT * FROM ACCIDENTINFO_C WHERE ACCIDENTID IS NULL;

SELECT a.*
FROM   ACCIDENTINFO_C a
WHERE  NOT EXISTS (SELECT 1 FROM MonCity.CARACCIDENT ca WHERE ca.ACCIDENTID = a.ACCIDENTID);

-- E4: only M936 remains; one positive price per type; no event recorded twice.
SELECT * FROM MAINTENANCE_C WHERE MAINTENANCEID IN ('M936', 'M2000');

SELECT MAINTENANCETYPE, MIN(MAINTENANCECOST) AS min_cost, MAX(MAINTENANCECOST) AS max_cost,
       COUNT(*) AS records
FROM   MAINTENANCE_C
GROUP  BY MAINTENANCETYPE
ORDER  BY MAINTENANCETYPE;

SELECT REGISTRATIONNO, MAINTENANCEDATE, MAINTENANCETYPE, TEAMID, COUNT(*) AS copies
FROM   MAINTENANCE_C
GROUP  BY REGISTRATIONNO, MAINTENANCEDATE, MAINTENANCETYPE, TEAMID
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS maintenance_records, SUM(MAINTENANCECOST) AS total_cost
FROM   MAINTENANCE_C;                                   -- 1,000 / 302,700

-- E5: every remaining passenger belongs to a valid faculty.
SELECT p.*
FROM   PASSENGER_C p
WHERE  NOT EXISTS (SELECT 1 FROM MonCity.FACULTY f WHERE f.FACULTYID = p.FACULTYID);

-- E6: corrected descriptions; the detection pattern now returns no rows.
SELECT ERRORCODE, ERRORMESSAGE FROM ERROR_C ORDER BY ERRORCODE;

SELECT ERRORCODE, ERRORMESSAGE
FROM   ERROR_C
WHERE  REGEXP_LIKE(ERRORMESSAGE, 'systeem|Unknow[^n]|:[^ ]');


-- =====================================================================================
-- 02 / C4 VERSION-1 IMPLEMENTATION (highest aggregation)
--   Grain declarations:
--   BookingFact     - one row per month x faculty x age group x car body type
--   MaintenanceFact - one row per maintenance type x car body type x maintenance team
--   AccidentFact    - one row per car x accident zone x damage severity x error code;
--                     NUM_OF_ACCIDENTS counts car-accident involvements (a two-car
--                     accident counts once for each car, as required per car).
--   Composite primary keys enforce each grain; foreign keys enforce every star join.
-- =====================================================================================

-- 02A / CONFORMED AND DESCRIPTIVE DIMENSIONS
CREATE TABLE FacultyDim AS
SELECT FACULTYID, FACULTYNAME, ZONE FROM MonCity.FACULTY;
ALTER TABLE FacultyDim ADD CONSTRAINT pk_facultydim PRIMARY KEY (FACULTYID);

CREATE TABLE CarBodyDim AS
SELECT DISTINCT CARBODYTYPE, NUMSEATS FROM MonCity.CAR;
ALTER TABLE CarBodyDim ADD CONSTRAINT pk_carbodydim PRIMARY KEY (CARBODYTYPE);

-- CarDim snowflakes to CarBodyDim: NUMSEATS is stored once, in CarBodyDim.
CREATE TABLE CarDim AS
SELECT REGISTRATIONNO, CARMODEL, MANUFACTURINGYEAR, CARBODYTYPE FROM MonCity.CAR;
ALTER TABLE CarDim ADD CONSTRAINT pk_cardim PRIMARY KEY (REGISTRATIONNO);
ALTER TABLE CarDim ADD CONSTRAINT fk_cardim_carbody
      FOREIGN KEY (CARBODYTYPE) REFERENCES CarBodyDim (CARBODYTYPE);

CREATE TABLE MaintenanceTypeDim AS
SELECT MAINTENANCETYPE, MAINTENANCEDESCRIPTION FROM MonCity.MAINTENANCETYPE;
ALTER TABLE MaintenanceTypeDim ADD CONSTRAINT pk_maintenancetypedim PRIMARY KEY (MAINTENANCETYPE);

CREATE TABLE ResearchCenterDim AS
SELECT CENTERID, CENTERNAME FROM MonCity.RESEARCHCENTER;
ALTER TABLE ResearchCenterDim ADD CONSTRAINT pk_researchcenterdim PRIMARY KEY (CENTERID);

CREATE TABLE ErrorDim AS
SELECT ERRORCODE, ERRORMESSAGE FROM ERROR_C;              -- cleaned labels (E6)
ALTER TABLE ErrorDim ADD CONSTRAINT pk_errordim PRIMARY KEY (ERRORCODE);

CREATE TABLE AccidentZoneDim AS
SELECT DISTINCT ACCIDENTZONE FROM ACCIDENTINFO_C;
ALTER TABLE AccidentZoneDim ADD CONSTRAINT pk_accidentzonedim PRIMARY KEY (ACCIDENTZONE);

CREATE TABLE SeverityDim AS
SELECT DISTINCT CAR_DAMAGE_SEVERITY,
       CASE CAR_DAMAGE_SEVERITY
            WHEN 'No damage'         THEN 0
            WHEN 'Very minor damage' THEN 1
            WHEN 'Minor damage'      THEN 2
            WHEN 'Moderate damage'   THEN 3
            WHEN 'Severe damage'     THEN 4
       END AS SEVERITY_RANK
FROM   ACCIDENTINFO_C;
ALTER TABLE SeverityDim ADD CONSTRAINT pk_severitydim PRIMARY KEY (CAR_DAMAGE_SEVERITY);

-- 02B / TEAM-CENTRE BRIDGE (M:N) - GroupList and WeightFactor live in TeamDim.
CREATE TABLE TeamDim AS
SELECT t.TEAMID, t.TEAMLEADER, g.CENTREGROUPLIST, 1 / g.CENTRE_COUNT AS WEIGHTFACTOR
FROM   MonCity.MAINTENANCETEAM t
JOIN  (SELECT TEAMID,
              LISTAGG(CENTERID, '_') WITHIN GROUP (ORDER BY CENTERID) AS CENTREGROUPLIST,
              COUNT(*) AS CENTRE_COUNT
       FROM   MonCity.BELONGTO
       GROUP  BY TEAMID) g
  ON   g.TEAMID = t.TEAMID;
ALTER TABLE TeamDim ADD CONSTRAINT pk_teamdim PRIMARY KEY (TEAMID);

CREATE TABLE TeamCenterBridge AS
SELECT TEAMID, CENTERID FROM MonCity.BELONGTO;
ALTER TABLE TeamCenterBridge ADD CONSTRAINT pk_teamcenterbridge PRIMARY KEY (TEAMID, CENTERID);
ALTER TABLE TeamCenterBridge ADD CONSTRAINT fk_bridge_team
      FOREIGN KEY (TEAMID) REFERENCES TeamDim (TEAMID);
ALTER TABLE TeamCenterBridge ADD CONSTRAINT fk_bridge_centre
      FOREIGN KEY (CENTERID) REFERENCES ResearchCenterDim (CENTERID);

-- 02C / USER-DEFINED DIMENSIONS
CREATE TABLE MonthDim (
    MONTHNO   NUMBER(2)   CONSTRAINT pk_monthdim PRIMARY KEY,
    MONTHNAME VARCHAR2(9) NOT NULL
);

INSERT INTO MonthDim VALUES (1,  'January');
INSERT INTO MonthDim VALUES (2,  'February');
INSERT INTO MonthDim VALUES (3,  'March');
INSERT INTO MonthDim VALUES (4,  'April');
INSERT INTO MonthDim VALUES (5,  'May');
INSERT INTO MonthDim VALUES (6,  'June');
INSERT INTO MonthDim VALUES (7,  'July');
INSERT INTO MonthDim VALUES (8,  'August');
INSERT INTO MonthDim VALUES (9,  'September');
INSERT INTO MonthDim VALUES (10, 'October');
INSERT INTO MonthDim VALUES (11, 'November');
INSERT INTO MonthDim VALUES (12, 'December');

CREATE TABLE AgeGroupDim (
    AGEGROUP VARCHAR2(20) CONSTRAINT pk_agegroupdim PRIMARY KEY,
    MIN_AGE  NUMBER       NOT NULL,
    MAX_AGE  NUMBER                      -- NULL = open-ended (60 and over)
);

INSERT INTO AgeGroupDim VALUES ('Young adults',       18, 35);
INSERT INTO AgeGroupDim VALUES ('Middle-aged adults', 36, 59);
INSERT INTO AgeGroupDim VALUES ('Old-aged adults',    60, NULL);
COMMIT;

-- 02D / BOOKING STAGE - one row per cleaned booking, so every derivation is traceable.
CREATE TABLE tempfact_booking AS
SELECT b.BOOKINGID, b.BOOKINGDATE, p.PASSENGERAGE, p.FACULTYID, c.CARBODYTYPE
FROM   BOOKING_C b
JOIN   PASSENGER_C p ON p.PASSENGERID    = b.PASSENGERID
JOIN   CarDim      c ON c.REGISTRATIONNO = b.REGISTRATIONNO;

ALTER TABLE tempfact_booking ADD (MONTHNO NUMBER(2), AGEGROUP VARCHAR2(20));

UPDATE tempfact_booking
SET    MONTHNO = EXTRACT(MONTH FROM BOOKINGDATE);

UPDATE tempfact_booking t
SET    AGEGROUP = (SELECT g.AGEGROUP
                   FROM   AgeGroupDim g
                   WHERE  t.PASSENGERAGE BETWEEN g.MIN_AGE AND NVL(g.MAX_AGE, t.PASSENGERAGE));
COMMIT;

-- Every staged booking received a month and an age group (expect 10,000 / 10,000 / 10,000).
SELECT COUNT(*) AS staged, COUNT(MONTHNO) AS with_month, COUNT(AGEGROUP) AS with_agegroup
FROM   tempfact_booking;

-- 02E / FACT TABLES
CREATE TABLE BookingFact AS
SELECT MONTHNO, FACULTYID, AGEGROUP, CARBODYTYPE,
       COUNT(*) AS NUM_OF_BOOKINGS
FROM   tempfact_booking
GROUP  BY MONTHNO, FACULTYID, AGEGROUP, CARBODYTYPE;

ALTER TABLE BookingFact ADD CONSTRAINT pk_bookingfact
      PRIMARY KEY (MONTHNO, FACULTYID, AGEGROUP, CARBODYTYPE);
ALTER TABLE BookingFact ADD CONSTRAINT fk_bookfact_month
      FOREIGN KEY (MONTHNO) REFERENCES MonthDim (MONTHNO);
ALTER TABLE BookingFact ADD CONSTRAINT fk_bookfact_faculty
      FOREIGN KEY (FACULTYID) REFERENCES FacultyDim (FACULTYID);
ALTER TABLE BookingFact ADD CONSTRAINT fk_bookfact_agegroup
      FOREIGN KEY (AGEGROUP) REFERENCES AgeGroupDim (AGEGROUP);
ALTER TABLE BookingFact ADD CONSTRAINT fk_bookfact_carbody
      FOREIGN KEY (CARBODYTYPE) REFERENCES CarBodyDim (CARBODYTYPE);

CREATE TABLE MaintenanceFact AS
SELECT m.MAINTENANCETYPE, c.CARBODYTYPE, m.TEAMID,
       COUNT(*)               AS NUM_OF_MAINTENANCE,
       SUM(m.MAINTENANCECOST) AS TOTAL_COST
FROM   MAINTENANCE_C m
JOIN   CarDim c ON c.REGISTRATIONNO = m.REGISTRATIONNO
GROUP  BY m.MAINTENANCETYPE, c.CARBODYTYPE, m.TEAMID;

ALTER TABLE MaintenanceFact ADD CONSTRAINT pk_maintenancefact
      PRIMARY KEY (MAINTENANCETYPE, CARBODYTYPE, TEAMID);
ALTER TABLE MaintenanceFact ADD CONSTRAINT fk_maintfact_type
      FOREIGN KEY (MAINTENANCETYPE) REFERENCES MaintenanceTypeDim (MAINTENANCETYPE);
ALTER TABLE MaintenanceFact ADD CONSTRAINT fk_maintfact_carbody
      FOREIGN KEY (CARBODYTYPE) REFERENCES CarBodyDim (CARBODYTYPE);
ALTER TABLE MaintenanceFact ADD CONSTRAINT fk_maintfact_team
      FOREIGN KEY (TEAMID) REFERENCES TeamDim (TEAMID);

CREATE TABLE AccidentFact AS
SELECT ca.REGISTRATIONNO, a.ACCIDENTZONE, a.CAR_DAMAGE_SEVERITY, a.ERRORCODE,
       COUNT(*) AS NUM_OF_ACCIDENTS
FROM   MonCity.CARACCIDENT ca
JOIN   ACCIDENTINFO_C a ON a.ACCIDENTID = ca.ACCIDENTID
GROUP  BY ca.REGISTRATIONNO, a.ACCIDENTZONE, a.CAR_DAMAGE_SEVERITY, a.ERRORCODE;

ALTER TABLE AccidentFact ADD CONSTRAINT pk_accidentfact
      PRIMARY KEY (REGISTRATIONNO, ACCIDENTZONE, CAR_DAMAGE_SEVERITY, ERRORCODE);
ALTER TABLE AccidentFact ADD CONSTRAINT fk_accfact_car
      FOREIGN KEY (REGISTRATIONNO) REFERENCES CarDim (REGISTRATIONNO);
ALTER TABLE AccidentFact ADD CONSTRAINT fk_accfact_zone
      FOREIGN KEY (ACCIDENTZONE) REFERENCES AccidentZoneDim (ACCIDENTZONE);
ALTER TABLE AccidentFact ADD CONSTRAINT fk_accfact_severity
      FOREIGN KEY (CAR_DAMAGE_SEVERITY) REFERENCES SeverityDim (CAR_DAMAGE_SEVERITY);
ALTER TABLE AccidentFact ADD CONSTRAINT fk_accfact_error
      FOREIGN KEY (ERRORCODE) REFERENCES ErrorDim (ERRORCODE);


-- =====================================================================================
-- 03 / VALIDATION - the warehouse reconciles to the cleaned sources.
-- =====================================================================================

-- 03A / Row counts of every Version-1 table.
SELECT 'FacultyDim' AS table_name, COUNT(*) AS row_count FROM FacultyDim
UNION ALL SELECT 'CarBodyDim',         COUNT(*) FROM CarBodyDim
UNION ALL SELECT 'CarDim',             COUNT(*) FROM CarDim
UNION ALL SELECT 'MaintenanceTypeDim', COUNT(*) FROM MaintenanceTypeDim
UNION ALL SELECT 'ResearchCenterDim',  COUNT(*) FROM ResearchCenterDim
UNION ALL SELECT 'ErrorDim',           COUNT(*) FROM ErrorDim
UNION ALL SELECT 'AccidentZoneDim',    COUNT(*) FROM AccidentZoneDim
UNION ALL SELECT 'SeverityDim',        COUNT(*) FROM SeverityDim
UNION ALL SELECT 'TeamDim',            COUNT(*) FROM TeamDim
UNION ALL SELECT 'TeamCenterBridge',   COUNT(*) FROM TeamCenterBridge
UNION ALL SELECT 'MonthDim',           COUNT(*) FROM MonthDim
UNION ALL SELECT 'AgeGroupDim',        COUNT(*) FROM AgeGroupDim
UNION ALL SELECT 'BookingFact',        COUNT(*) FROM BookingFact
UNION ALL SELECT 'MaintenanceFact',    COUNT(*) FROM MaintenanceFact
UNION ALL SELECT 'AccidentFact',       COUNT(*) FROM AccidentFact;
-- Expected: 5, 3, 30, 5, 4, 5, 4, 5, 5, 12, 12, 3, 468, 75, 550

-- 03B / Control totals: every fact measure equals its cleaned-source count or sum.
SELECT r.control_total, r.warehouse_value, r.source_value,
       CASE WHEN r.warehouse_value = r.source_value THEN 'RECONCILED' ELSE 'CHECK' END AS status
FROM  (SELECT 'Bookings' AS control_total,
              (SELECT SUM(NUM_OF_BOOKINGS) FROM BookingFact) AS warehouse_value,
              (SELECT COUNT(*) FROM BOOKING_C)               AS source_value
       FROM DUAL
       UNION ALL
       SELECT 'Maintenance records',
              (SELECT SUM(NUM_OF_MAINTENANCE) FROM MaintenanceFact),
              (SELECT COUNT(*) FROM MAINTENANCE_C)
       FROM DUAL
       UNION ALL
       SELECT 'Maintenance cost',
              (SELECT SUM(TOTAL_COST) FROM MaintenanceFact),
              (SELECT SUM(MAINTENANCECOST) FROM MAINTENANCE_C)
       FROM DUAL
       UNION ALL
       SELECT 'Accident records (car-accident involvements)',
              (SELECT SUM(NUM_OF_ACCIDENTS) FROM AccidentFact),
              (SELECT COUNT(*) FROM MonCity.CARACCIDENT ca
                               JOIN ACCIDENTINFO_C a ON a.ACCIDENTID = ca.ACCIDENTID)
       FROM DUAL) r
ORDER  BY r.control_total;
-- Expected: 1,000 / 1,000; 302,700 / 302,700; 1,000 / 1,000; 10,000 / 10,000

-- 03C / Distinct accidents behind the 1,000 car-accident records (8 involve two cars).
SELECT COUNT(*) AS distinct_accidents FROM ACCIDENTINFO_C;          -- 992

-- 03D / Bridge weights sum to 1 per team, so weighted allocation preserves total cost.
SELECT t.TEAMID, t.CENTREGROUPLIST, t.WEIGHTFACTOR,
       COUNT(*)                  AS centres,
       t.WEIGHTFACTOR * COUNT(*) AS weight_sum
FROM   TeamDim t
JOIN   TeamCenterBridge b ON b.TEAMID = t.TEAMID
GROUP  BY t.TEAMID, t.CENTREGROUPLIST, t.WEIGHTFACTOR
ORDER  BY t.TEAMID;


-- =====================================================================================
-- 04 / C3 ANALYTICAL QUESTIONS answered from Version-1
-- =====================================================================================

-- Q1 Bookings by IT-faculty passengers in July using a bus.                  (82)
SELECT SUM(f.NUM_OF_BOOKINGS) AS bookings
FROM   BookingFact f
JOIN   FacultyDim d ON d.FACULTYID = f.FACULTYID
JOIN   MonthDim   m ON m.MONTHNO   = f.MONTHNO
WHERE  d.FACULTYID = 'FIT' AND m.MONTHNAME = 'July' AND f.CARBODYTYPE = 'Bus';

-- Q2 Bookings by passenger age group.            (4,085 / 5,062 / 853)
SELECT g.AGEGROUP, g.MIN_AGE, g.MAX_AGE, SUM(f.NUM_OF_BOOKINGS) AS bookings
FROM   BookingFact f
JOIN   AgeGroupDim g ON g.AGEGROUP = f.AGEGROUP
GROUP  BY g.AGEGROUP, g.MIN_AGE, g.MAX_AGE
ORDER  BY g.MIN_AGE;

-- Q3 Maintenance records involving at least one team from CE04.            (627)
--    Membership filter, NOT a weighted allocation: each record is counted once.
SELECT SUM(f.NUM_OF_MAINTENANCE) AS maintenance_records
FROM   MaintenanceFact f
WHERE  f.TEAMID IN (SELECT b.TEAMID FROM TeamCenterBridge b WHERE b.CENTERID = 'CE04');

-- Q4 Total maintenance cost of each maintenance type for Mini Bus.
--    (M001 7,300 / M002 14,200 / M003 17,700 / M004 18,400 / M005 31,000)
SELECT t.MAINTENANCETYPE, t.MAINTENANCEDESCRIPTION, SUM(f.TOTAL_COST) AS total_cost
FROM   MaintenanceFact f
JOIN   MaintenanceTypeDim t ON t.MAINTENANCETYPE = f.MAINTENANCETYPE
WHERE  f.CARBODYTYPE = 'Mini Bus'
GROUP  BY t.MAINTENANCETYPE, t.MAINTENANCEDESCRIPTION
ORDER  BY t.MAINTENANCETYPE;

-- Q5 Accidents recorded in ZoneA for Car01.                                  (10)
SELECT SUM(NUM_OF_ACCIDENTS) AS accidents
FROM   AccidentFact
WHERE  ACCIDENTZONE = 'ZoneA' AND REGISTRATIONNO = 'Car01';

-- Q6 Accidents per error code at ZoneB for Car06.  (Error001 2, Error003 3, Error004 1, Error005 1)
SELECT e.ERRORCODE, e.ERRORMESSAGE, SUM(f.NUM_OF_ACCIDENTS) AS accidents
FROM   AccidentFact f
JOIN   ErrorDim e ON e.ERRORCODE = f.ERRORCODE
WHERE  f.ACCIDENTZONE = 'ZoneB' AND f.REGISTRATIONNO = 'Car06'
GROUP  BY e.ERRORCODE, e.ERRORMESSAGE
ORDER  BY e.ERRORCODE;

-- Q7 Accidents with severe damage inflicted on Car05.                          (7)
SELECT SUM(NUM_OF_ACCIDENTS) AS accidents
FROM   AccidentFact
WHERE  CAR_DAMAGE_SEVERITY = 'Severe damage' AND REGISTRATIONNO = 'Car05';


-- =====================================================================================
-- 05 / C5 ANALYSIS - every figure in the findings report, from Version-1 tables only.
--      Rates that combine two facts are computed per CarBodyDim member (drill-across on
--      the conformed dimension); fact rows are never joined to each other.
-- =====================================================================================

-- C5.2 Finding 1 / C5.9 Finding 8 (Visuals 1 and 9) - demand, per-vehicle and per-seat use.
SELECT b.CARBODYTYPE,
       v.VEHICLES,
       cb.NUMSEATS,
       b.BOOKINGS,
       ROUND(100 * b.BOOKINGS / SUM(b.BOOKINGS) OVER (), 2)   AS share_pct,
       ROUND(b.BOOKINGS / v.VEHICLES, 1)                      AS bookings_per_vehicle,
       ROUND(b.BOOKINGS / (v.VEHICLES * cb.NUMSEATS), 1)      AS bookings_per_seat
FROM  (SELECT CARBODYTYPE, SUM(NUM_OF_BOOKINGS) AS BOOKINGS
       FROM   BookingFact GROUP BY CARBODYTYPE) b
JOIN  (SELECT CARBODYTYPE, COUNT(*) AS VEHICLES
       FROM   CarDim GROUP BY CARBODYTYPE) v ON v.CARBODYTYPE = b.CARBODYTYPE
JOIN   CarBodyDim cb ON cb.CARBODYTYPE = b.CARBODYTYPE
ORDER  BY b.CARBODYTYPE;

-- C5.2 Finding 1 / Visual 2 - calendar-month profile pooled over 2015-2021.
--      DAYS_2015_2021 = calendar days of that month across the seven years (2016, 2020 leap).
SELECT m.MONTHNO, m.MONTHNAME,
       SUM(f.NUM_OF_BOOKINGS)                                                    AS bookings,
       SUM(CASE WHEN f.CARBODYTYPE = 'Bus'          THEN f.NUM_OF_BOOKINGS ELSE 0 END) AS bus,
       SUM(CASE WHEN f.CARBODYTYPE = 'Mini Bus'     THEN f.NUM_OF_BOOKINGS ELSE 0 END) AS mini_bus,
       SUM(CASE WHEN f.CARBODYTYPE = 'People Mover' THEN f.NUM_OF_BOOKINGS ELSE 0 END) AS people_mover,
       ROUND(SUM(f.NUM_OF_BOOKINGS) /
             CASE WHEN m.MONTHNO = 2 THEN 198
                  WHEN m.MONTHNO IN (4, 6, 9, 11) THEN 210
                  ELSE 217 END, 2)                                               AS bookings_per_day
FROM   BookingFact f
JOIN   MonthDim m ON m.MONTHNO = f.MONTHNO
GROUP  BY m.MONTHNO, m.MONTHNAME
ORDER  BY m.MONTHNO;

-- C5.3 Finding 2 / Visuals 3 and 4 - severity by body type and rates per 1,000 bookings.
WITH acc AS (
    SELECT c.CARBODYTYPE,
           SUM(a.NUM_OF_ACCIDENTS)                                                    AS all_records,
           SUM(CASE WHEN s.SEVERITY_RANK = 0  THEN a.NUM_OF_ACCIDENTS ELSE 0 END)     AS no_damage,
           SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END)     AS any_damage,
           SUM(CASE WHEN s.SEVERITY_RANK >= 3 THEN a.NUM_OF_ACCIDENTS ELSE 0 END)     AS moderate_severe,
           SUM(CASE WHEN s.SEVERITY_RANK = 4  THEN a.NUM_OF_ACCIDENTS ELSE 0 END)     AS severe
    FROM   AccidentFact a
    JOIN   CarDim      c ON c.REGISTRATIONNO      = a.REGISTRATIONNO
    JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
    GROUP  BY c.CARBODYTYPE),
bk AS (
    SELECT CARBODYTYPE, SUM(NUM_OF_BOOKINGS) AS bookings
    FROM   BookingFact GROUP BY CARBODYTYPE)
SELECT acc.CARBODYTYPE, bk.bookings, acc.all_records, acc.no_damage, acc.any_damage,
       acc.moderate_severe, acc.severe,
       ROUND(1000 * acc.all_records / bk.bookings, 2) AS all_per_1000,
       ROUND(1000 * acc.no_damage   / bk.bookings, 2) AS no_damage_per_1000,
       ROUND(1000 * acc.any_damage  / bk.bookings, 1) AS damage_per_1000,
       ROUND(1000 * acc.severe      / bk.bookings, 1) AS severe_per_1000,
       ROUND(100  * acc.no_damage   / acc.all_records, 1) AS pct_no_damage
FROM   acc
JOIN   bk ON bk.CARBODYTYPE = acc.CARBODYTYPE
ORDER  BY acc.CARBODYTYPE;

-- C5.3 Finding 2 - Bus and Mini Bus combined vs People Mover (94.5 vs 0.9 per 1,000).
SELECT CASE WHEN c.CARBODYTYPE = 'People Mover' THEN 'People Mover'
            ELSE 'Bus + Mini Bus' END                                   AS vehicle_group,
       SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS damage_records
FROM   AccidentFact a
JOIN   CarDim      c ON c.REGISTRATIONNO      = a.REGISTRATIONNO
JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
GROUP  BY CASE WHEN c.CARBODYTYPE = 'People Mover' THEN 'People Mover'
               ELSE 'Bus + Mini Bus' END;
--   Bus + Mini Bus: 624 damage records / 6,604 bookings = 94.5 per 1,000;
--   People Mover:     3 damage records / 3,396 bookings =  0.9 per 1,000.

-- C5.3 Finding 2 / Visual 3 - severity composition (share of each body type's records).
SELECT c.CARBODYTYPE, s.SEVERITY_RANK, s.CAR_DAMAGE_SEVERITY,
       SUM(a.NUM_OF_ACCIDENTS) AS records,
       ROUND(100 * SUM(a.NUM_OF_ACCIDENTS)
                 / SUM(SUM(a.NUM_OF_ACCIDENTS)) OVER (PARTITION BY c.CARBODYTYPE), 2) AS pct_of_body_type
FROM   AccidentFact a
JOIN   CarDim      c ON c.REGISTRATIONNO      = a.REGISTRATIONNO
JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
GROUP  BY c.CARBODYTYPE, s.SEVERITY_RANK, s.CAR_DAMAGE_SEVERITY
ORDER  BY c.CARBODYTYPE, s.SEVERITY_RANK;

-- C5.4 Finding 3 / Visual 5 - error code x body type (Low Battery x People Mover = 368).
SELECT e.ERRORCODE, e.ERRORMESSAGE,
       SUM(CASE WHEN c.CARBODYTYPE = 'Bus'          THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS bus,
       SUM(CASE WHEN c.CARBODYTYPE = 'Mini Bus'     THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS mini_bus,
       SUM(CASE WHEN c.CARBODYTYPE = 'People Mover' THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS people_mover,
       SUM(a.NUM_OF_ACCIDENTS)                                                          AS total,
       ROUND(100 * SUM(a.NUM_OF_ACCIDENTS) / SUM(SUM(a.NUM_OF_ACCIDENTS)) OVER (), 1)  AS pct_of_all
FROM   AccidentFact a
JOIN   CarDim   c ON c.REGISTRATIONNO = a.REGISTRATIONNO
JOIN   ErrorDim e ON e.ERRORCODE      = a.ERRORCODE
GROUP  BY e.ERRORCODE, e.ERRORMESSAGE
ORDER  BY total DESC;

-- C5.4 Finding 3 - error x severity: Low Battery <-> 'No damage' is one-to-one (373 = 373).
SELECT a.ERRORCODE,
       SUM(CASE WHEN s.SEVERITY_RANK = 0  THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS no_damage,
       SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS any_damage
FROM   AccidentFact a
JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
GROUP  BY a.ERRORCODE
ORDER  BY a.ERRORCODE;

-- C5.4 Finding 3 - Low-Battery events on each People Mover (29-45 per car, mean 36.8).
SELECT c.REGISTRATIONNO, c.CARMODEL, c.MANUFACTURINGYEAR,
       SUM(a.NUM_OF_ACCIDENTS) AS low_battery_events
FROM   AccidentFact a
JOIN   CarDim c ON c.REGISTRATIONNO = a.REGISTRATIONNO
WHERE  a.ERRORCODE = 'Error002' AND c.CARBODYTYPE = 'People Mover'
GROUP  BY c.REGISTRATIONNO, c.CARMODEL, c.MANUFACTURINGYEAR
ORDER  BY c.REGISTRATIONNO;

-- C5.5 Finding 4 / Visual 6 - damage records by error code (Low Battery has none).
SELECT e.ERRORCODE, e.ERRORMESSAGE,
       SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END)      AS damage_records,
       SUM(CASE WHEN s.SEVERITY_RANK = 4  THEN a.NUM_OF_ACCIDENTS ELSE 0 END)      AS severe_records,
       ROUND(100 * SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END)
                 / SUM(SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END)) OVER (), 1)
                                                                                    AS pct_of_damage,
       ROUND(100 * SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END)
                 / SUM(SUM(a.NUM_OF_ACCIDENTS)) OVER (), 1)                         AS pct_of_all_records,
       SUM(CASE WHEN s.SEVERITY_RANK >= 1 AND c.CARBODYTYPE <> 'People Mover'
                THEN a.NUM_OF_ACCIDENTS ELSE 0 END)                                 AS damage_on_bus_minibus
FROM   AccidentFact a
JOIN   CarDim      c ON c.REGISTRATIONNO      = a.REGISTRATIONNO
JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
JOIN   ErrorDim    e ON e.ERRORCODE           = a.ERRORCODE
GROUP  BY e.ERRORCODE, e.ERRORMESSAGE
ORDER  BY damage_records DESC;

-- C5.6 Finding 5 / Visuals 7 and 8 - maintenance cost per booking by type and body type,
--      with the Bus - Mini Bus gap (drill-across on CarBodyDim).
WITH mc AS (
    SELECT MAINTENANCETYPE, CARBODYTYPE, SUM(TOTAL_COST) AS type_cost
    FROM   MaintenanceFact GROUP BY MAINTENANCETYPE, CARBODYTYPE),
bk AS (
    SELECT CARBODYTYPE, SUM(NUM_OF_BOOKINGS) AS bookings
    FROM   BookingFact GROUP BY CARBODYTYPE),
cpb AS (
    SELECT c.MAINTENANCETYPE, c.CARBODYTYPE, c.type_cost / b.bookings AS cost_per_booking
    FROM   mc c JOIN bk b ON b.CARBODYTYPE = c.CARBODYTYPE)
SELECT t.MAINTENANCETYPE, t.MAINTENANCEDESCRIPTION,
       ROUND(SUM(CASE WHEN p.CARBODYTYPE = 'Bus'          THEN p.cost_per_booking END), 2) AS bus,
       ROUND(SUM(CASE WHEN p.CARBODYTYPE = 'Mini Bus'     THEN p.cost_per_booking END), 2) AS mini_bus,
       ROUND(SUM(CASE WHEN p.CARBODYTYPE = 'People Mover' THEN p.cost_per_booking END), 2) AS people_mover,
       ROUND(SUM(CASE WHEN p.CARBODYTYPE = 'Bus'      THEN p.cost_per_booking END)
           - SUM(CASE WHEN p.CARBODYTYPE = 'Mini Bus' THEN p.cost_per_booking END), 2)     AS bus_minus_mini_bus
FROM   cpb p
JOIN   MaintenanceTypeDim t ON t.MAINTENANCETYPE = p.MAINTENANCETYPE
GROUP  BY t.MAINTENANCETYPE, t.MAINTENANCEDESCRIPTION
ORDER  BY t.MAINTENANCETYPE;
--   Totals: Bus 34.49, Mini Bus 26.74, People Mover 29.62; gap 7.74, of which
--   M004 + M005 = 2.95 + 4.16 = 7.12 (91.9%).

-- C5.6 / C5.7 Findings 5-6 - cost, records per 100 bookings, average cost per record,
--      and safety rates side by side for each body type.
WITH m AS (
    SELECT CARBODYTYPE, SUM(NUM_OF_MAINTENANCE) AS records, SUM(TOTAL_COST) AS total_cost
    FROM   MaintenanceFact GROUP BY CARBODYTYPE),
bk AS (
    SELECT CARBODYTYPE, SUM(NUM_OF_BOOKINGS) AS bookings
    FROM   BookingFact GROUP BY CARBODYTYPE),
acc AS (
    SELECT c.CARBODYTYPE,
           SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS damage,
           SUM(CASE WHEN s.SEVERITY_RANK = 4  THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS severe
    FROM   AccidentFact a
    JOIN   CarDim      c ON c.REGISTRATIONNO      = a.REGISTRATIONNO
    JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
    GROUP  BY c.CARBODYTYPE)
SELECT m.CARBODYTYPE, m.records, m.total_cost, bk.bookings,
       ROUND(m.total_cost / bk.bookings, 2)     AS cost_per_booking,
       ROUND(100 * m.records / bk.bookings, 2)  AS records_per_100_bookings,
       ROUND(m.total_cost / m.records, 2)       AS avg_cost_per_record,
       ROUND(1000 * acc.damage / bk.bookings, 1) AS damage_per_1000,
       ROUND(1000 * acc.severe / bk.bookings, 1) AS severe_per_1000
FROM   m
JOIN   bk  ON bk.CARBODYTYPE  = m.CARBODYTYPE
JOIN   acc ON acc.CARBODYTYPE = m.CARBODYTYPE
ORDER  BY m.CARBODYTYPE;

-- C5.8 Finding 7 - where maintenance goes vs where failures occur, per body type.
WITH m AS (
    SELECT CARBODYTYPE,
           SUM(NUM_OF_MAINTENANCE)                                                          AS jobs,
           SUM(CASE WHEN MAINTENANCETYPE = 'M004' THEN NUM_OF_MAINTENANCE ELSE 0 END)       AS battery_jobs,
           SUM(CASE WHEN MAINTENANCETYPE IN ('M002', 'M003') THEN NUM_OF_MAINTENANCE ELSE 0 END) AS sensor_lidar_jobs,
           SUM(CASE WHEN MAINTENANCETYPE IN ('M002', 'M003') THEN TOTAL_COST ELSE 0 END)    AS sensor_lidar_cost
    FROM   MaintenanceFact GROUP BY CARBODYTYPE),
f AS (
    SELECT c.CARBODYTYPE,
           SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END)           AS damage,
           SUM(CASE WHEN a.ERRORCODE = 'Error002' THEN a.NUM_OF_ACCIDENTS ELSE 0 END)       AS low_battery,
           SUM(CASE WHEN a.ERRORCODE IN ('Error001', 'Error003', 'Error004')
                    THEN a.NUM_OF_ACCIDENTS ELSE 0 END)                                     AS sensing_damage
    FROM   AccidentFact a
    JOIN   CarDim      c ON c.REGISTRATIONNO      = a.REGISTRATIONNO
    JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
    GROUP  BY c.CARBODYTYPE)
SELECT m.CARBODYTYPE,
       m.jobs,   ROUND(100 * m.jobs   / SUM(m.jobs)   OVER (), 1) AS pct_of_jobs,
       f.damage, ROUND(100 * f.damage / SUM(f.damage) OVER (), 1) AS pct_of_damage,
       m.battery_jobs, f.low_battery,
       m.sensor_lidar_jobs, m.sensor_lidar_cost, f.sensing_damage
FROM   m
JOIN   f ON f.CARBODYTYPE = m.CARBODYTYPE
ORDER  BY m.CARBODYTYPE;

-- C5.10 Finding 9 - centre cost: weighted (bridge WEIGHTFACTOR) vs naive unweighted join.
SELECT r.CENTERID, r.CENTERNAME,
       SUM(f.TOTAL_COST * t.WEIGHTFACTOR)                                         AS weighted_cost,
       ROUND(100 * SUM(f.TOTAL_COST * t.WEIGHTFACTOR)
                 / SUM(SUM(f.TOTAL_COST * t.WEIGHTFACTOR)) OVER (), 1)           AS weighted_share_pct,
       SUM(f.TOTAL_COST)                                                          AS unweighted_cost
FROM   MaintenanceFact f
JOIN   TeamDim           t ON t.TEAMID   = f.TEAMID
JOIN   TeamCenterBridge  b ON b.TEAMID   = t.TEAMID
JOIN   ResearchCenterDim r ON r.CENTERID = b.CENTERID
GROUP  BY r.CENTERID, r.CENTERNAME
ORDER  BY r.CENTERID;
--   Weighted total 302,700 (= MaintenanceFact); unweighted total 752,400 (2.49x overstated).

-- C5.12 Negative findings - accident and damage records by zone.
SELECT a.ACCIDENTZONE,
       SUM(a.NUM_OF_ACCIDENTS)                                                AS all_records,
       SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS damage_records
FROM   AccidentFact a
JOIN   SeverityDim s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
GROUP  BY a.ACCIDENTZONE
ORDER  BY a.ACCIDENTZONE;

-- C5.12 Negative findings - body-type split within each faculty and each age group.
SELECT 'Faculty' AS grouping_dim, d.FACULTYID AS member_value,
       SUM(f.NUM_OF_BOOKINGS) AS bookings,
       ROUND(100 * SUM(CASE WHEN f.CARBODYTYPE = 'Bus'          THEN f.NUM_OF_BOOKINGS ELSE 0 END) / SUM(f.NUM_OF_BOOKINGS), 1) AS bus_pct,
       ROUND(100 * SUM(CASE WHEN f.CARBODYTYPE = 'Mini Bus'     THEN f.NUM_OF_BOOKINGS ELSE 0 END) / SUM(f.NUM_OF_BOOKINGS), 1) AS mini_bus_pct,
       ROUND(100 * SUM(CASE WHEN f.CARBODYTYPE = 'People Mover' THEN f.NUM_OF_BOOKINGS ELSE 0 END) / SUM(f.NUM_OF_BOOKINGS), 1) AS people_mover_pct
FROM   BookingFact f
JOIN   FacultyDim d ON d.FACULTYID = f.FACULTYID
GROUP  BY d.FACULTYID
UNION ALL
SELECT 'Age group', g.AGEGROUP,
       SUM(f.NUM_OF_BOOKINGS),
       ROUND(100 * SUM(CASE WHEN f.CARBODYTYPE = 'Bus'          THEN f.NUM_OF_BOOKINGS ELSE 0 END) / SUM(f.NUM_OF_BOOKINGS), 1),
       ROUND(100 * SUM(CASE WHEN f.CARBODYTYPE = 'Mini Bus'     THEN f.NUM_OF_BOOKINGS ELSE 0 END) / SUM(f.NUM_OF_BOOKINGS), 1),
       ROUND(100 * SUM(CASE WHEN f.CARBODYTYPE = 'People Mover' THEN f.NUM_OF_BOOKINGS ELSE 0 END) / SUM(f.NUM_OF_BOOKINGS), 1)
FROM   BookingFact f
JOIN   AgeGroupDim g ON g.AGEGROUP = f.AGEGROUP
GROUP  BY g.AGEGROUP
ORDER  BY 1, 3 DESC;

-- C5.12 Negative findings - accidents per car (management's per-car view) with build year.
SELECT c.CARBODYTYPE, c.REGISTRATIONNO, c.CARMODEL, c.MANUFACTURINGYEAR,
       SUM(a.NUM_OF_ACCIDENTS)                                                AS accident_records,
       SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS damage_records,
       SUM(CASE WHEN s.SEVERITY_RANK = 4  THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS severe_records
FROM   CarDim c
JOIN   AccidentFact a ON a.REGISTRATIONNO      = c.REGISTRATIONNO
JOIN   SeverityDim  s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
GROUP  BY c.CARBODYTYPE, c.REGISTRATIONNO, c.CARMODEL, c.MANUFACTURINGYEAR
ORDER  BY c.CARBODYTYPE, c.REGISTRATIONNO;

-- C5.12 Negative findings - damage per car by build-year band within each body type.
WITH per_car AS (
    SELECT c.REGISTRATIONNO, c.CARBODYTYPE, c.MANUFACTURINGYEAR,
           SUM(CASE WHEN s.SEVERITY_RANK >= 1 THEN a.NUM_OF_ACCIDENTS ELSE 0 END) AS damage_records
    FROM   CarDim c
    JOIN   AccidentFact a ON a.REGISTRATIONNO      = c.REGISTRATIONNO
    JOIN   SeverityDim  s ON s.CAR_DAMAGE_SEVERITY = a.CAR_DAMAGE_SEVERITY
    GROUP  BY c.REGISTRATIONNO, c.CARBODYTYPE, c.MANUFACTURINGYEAR)
SELECT CARBODYTYPE,
       CASE WHEN CARBODYTYPE = 'Bus'      AND MANUFACTURINGYEAR <= 2009 THEN '2006-2009'
            WHEN CARBODYTYPE = 'Bus'                                    THEN '2010-2011'
            WHEN CARBODYTYPE = 'Mini Bus' AND MANUFACTURINGYEAR <= 2010 THEN '2008-2010'
            WHEN CARBODYTYPE = 'Mini Bus'                               THEN '2012-2013'
            WHEN MANUFACTURINGYEAR <= 2013                              THEN '2012-2013'
            ELSE '2014' END                                            AS build_years,
       COUNT(*)                         AS cars,
       ROUND(AVG(damage_records), 1)    AS damage_per_car
FROM   per_car
GROUP  BY CARBODYTYPE,
          CASE WHEN CARBODYTYPE = 'Bus'      AND MANUFACTURINGYEAR <= 2009 THEN '2006-2009'
               WHEN CARBODYTYPE = 'Bus'                                    THEN '2010-2011'
               WHEN CARBODYTYPE = 'Mini Bus' AND MANUFACTURINGYEAR <= 2010 THEN '2008-2010'
               WHEN CARBODYTYPE = 'Mini Bus'                               THEN '2012-2013'
               WHEN MANUFACTURINGYEAR <= 2013                              THEN '2012-2013'
               ELSE '2014' END
ORDER  BY CARBODYTYPE, build_years;


-- C5.16 Reproducibility - the two representative queries quoted in the report.
-- Maintenance cost per booking by body type: drill-across on the conformed CarBodyDim
WITH mc AS (SELECT CARBODYTYPE, SUM(TOTAL_COST) AS total_cost
            FROM MaintenanceFact GROUP BY CARBODYTYPE),
     bk AS (SELECT CARBODYTYPE, SUM(NUM_OF_BOOKINGS) AS bookings
            FROM BookingFact GROUP BY CARBODYTYPE)
SELECT mc.CARBODYTYPE, ROUND(mc.total_cost / bk.bookings, 2) AS cost_per_booking
FROM   mc JOIN bk ON bk.CARBODYTYPE = mc.CARBODYTYPE;

-- Centre cost allocated exactly once through the bridge weight factor
SELECT r.CENTERID, SUM(f.TOTAL_COST * t.WEIGHTFACTOR) AS weighted_cost
FROM   MaintenanceFact f
JOIN   TeamDim t            ON t.TEAMID   = f.TEAMID
JOIN   TeamCenterBridge b   ON b.TEAMID   = t.TEAMID
JOIN   ResearchCenterDim r  ON r.CENTERID = b.CENTERID
GROUP  BY r.CENTERID;


-- =====================================================================================
-- 06 / C4 SCREENSHOT QUERIES - Version-1 table structure and contents.
-- =====================================================================================
DESC FacultyDim;
DESC CarBodyDim;
DESC CarDim;
DESC MaintenanceTypeDim;
DESC ResearchCenterDim;
DESC ErrorDim;
DESC AccidentZoneDim;
DESC SeverityDim;
DESC TeamDim;
DESC TeamCenterBridge;
DESC MonthDim;
DESC AgeGroupDim;
DESC BookingFact;
DESC MaintenanceFact;
DESC AccidentFact;

SELECT * FROM FacultyDim         ORDER BY FACULTYID;
SELECT * FROM CarBodyDim         ORDER BY CARBODYTYPE;
SELECT * FROM CarDim             ORDER BY REGISTRATIONNO;
SELECT * FROM MaintenanceTypeDim ORDER BY MAINTENANCETYPE;
SELECT * FROM ResearchCenterDim  ORDER BY CENTERID;
SELECT * FROM ErrorDim           ORDER BY ERRORCODE;
SELECT * FROM AccidentZoneDim    ORDER BY ACCIDENTZONE;
SELECT * FROM SeverityDim        ORDER BY SEVERITY_RANK;
SELECT * FROM TeamDim            ORDER BY TEAMID;
SELECT * FROM TeamCenterBridge   ORDER BY TEAMID, CENTERID;
SELECT * FROM MonthDim           ORDER BY MONTHNO;
SELECT * FROM AgeGroupDim        ORDER BY MIN_AGE;
SELECT * FROM BookingFact        ORDER BY MONTHNO, FACULTYID, AGEGROUP, CARBODYTYPE;
SELECT * FROM MaintenanceFact    ORDER BY MAINTENANCETYPE, CARBODYTYPE, TEAMID;
SELECT * FROM AccidentFact       ORDER BY REGISTRATIONNO, ACCIDENTZONE, CAR_DAMAGE_SEVERITY, ERRORCODE;

-- Constraints that implement the design (PK, FK, CHECK) - optional evidence screenshot.
SELECT table_name, constraint_name, constraint_type, r_constraint_name
FROM   user_constraints
WHERE  table_name IN ('BOOKINGFACT', 'MAINTENANCEFACT', 'ACCIDENTFACT', 'CARDIM', 'TEAMCENTERBRIDGE')
AND    constraint_type IN ('P', 'R')
ORDER  BY table_name, constraint_type, constraint_name;
