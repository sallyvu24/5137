/* PART 1 — C2 EXPLORATION */
-- First, I review the content of every table 
SELECT * FROM MonCity.FACULTY;         
SELECT * FROM MonCity.PASSENGER;
SELECT * FROM MonCity.CAR;             
SELECT * FROM MonCity.BOOKING;
SELECT * FROM MonCity.MAINTENANCE;     
SELECT * FROM MonCity.MAINTENANCETYPE;
SELECT * FROM MonCity.MAINTENANCETEAM; 
SELECT * FROM MonCity.BELONGTO;
SELECT * FROM MonCity.RESEARCHCENTER;  
SELECT * FROM MonCity.ACCIDENTINFO;
SELECT * FROM MonCity.CARACCIDENT;     
SELECT * FROM MonCity.ERROR;

-- Volume + primary-key uniqueness  (a gap => duplicate or missing PK)
SELECT
	COUNT(*) AS n,
	COUNT(DISTINCT BOOKINGID) AS n_pk
FROM
	MonCity.BOOKING;        -- 10001 vs 10000  => 1 DUP
	
SELECT
	COUNT(*) AS n,
	COUNT(ACCIDENTID) AS n_notnull
FROM
	MonCity.ACCIDENTINFO; -- 994 vs 993 => 1 NULL PK
-- Running duplicate check, there is only BOOKING noticed having a duplicate PK
-- while every other table's PK is unique.

-- (b) Content + domain ranges check
-- There are 107 Students and 47 Staffs recorded
SELECT
	PASSENGERROLE,
	COUNT(*)
FROM
	MonCity.PASSENGER
GROUP BY
	PASSENGERROLE;       

-- The min-max range is from 18 to 70 => valid
SELECT
	MIN(PASSENGERAGE),
	MAX(PASSENGERAGE)
FROM
	MonCity.PASSENGER;                 

-- Quality check notices a negative value invalid 
-- in maintenance cost as min (= -200)
SELECT
	MIN(MAINTENANCECOST),
	MAX(MAINTENANCECOST)
FROM
	MonCity.MAINTENANCE;           

-- (c) Invalid-FK (relationship) checks
SELECT
	PASSENGERID,
	FACULTYID
FROM
	MonCity.PASSENGER
WHERE
	FACULTYID NOT IN (
	SELECT
		FACULTYID
	FROM
		MonCity.FACULTY);    -- U163 = 'Alienware'

SELECT
	ACCIDENTID,
	ERRORCODE
FROM
	MonCity.ACCIDENTINFO
WHERE
	ERRORCODE NOT IN (
	SELECT
		ERRORCODE
	FROM
		MonCity.ERROR);      -- A2000 = 'Error010'

/* PART 2 — C2 DATA CLEANING 
   Types found: 1 Duplication, 2 Relationship(x2 invalid FK), 3 Incorrect(out-of-range), 4 Null-PK.
   (Type "Inconsistent values" was checked and NOT present.) */

-- Create new table Booking
-- Type 1: Duplication  -> rebuild with DISTINCT  (10001 -> 10000)
CREATE TABLE BOOKING_C AS
SELECT
	DISTINCT *
FROM
	MonCity.BOOKING;

-- Create new table Passenger
-- Type 2: Relationship  -> DELETE invalid-FK rows
CREATE TABLE PASSENGER_C AS
SELECT
	*
FROM
	MonCity.PASSENGER;

-- drops U163 (0 bookings -> loss-free)
DELETE
FROM
	PASSENGER_C
WHERE
	FACULTYID NOT IN (
	SELECT
		FACULTYID
	FROM
		MonCity.FACULTY);  

-- Create new table AccidentInfo
CREATE TABLE ACCIDENTINFO_C AS
SELECT
	*
FROM
	MonCity.ACCIDENTINFO;

DELETE
FROM
	ACCIDENTINFO_C
WHERE
	ERRORCODE NOT IN (
	SELECT
		ERRORCODE
	FROM
		MonCity.ERROR);    -- drops A2000 (not car-linked)

-- Create new table Maintenance		
-- Type 3 INCORRECT (out of range) -> DELETE
CREATE TABLE MAINTENANCE_C AS
SELECT
	*
FROM
	MonCity.MAINTENANCE;

-- drops M2000 (-200)
DELETE
FROM
	MAINTENANCE_C
WHERE
	MAINTENANCECOST < 0;                                      

-- Type 4 NULL PK -> DELETE
-- Drops blank-id accident (not car-linked)
DELETE
FROM
	ACCIDENTINFO_C
WHERE
	ACCIDENTID IS NULL;              


-- BEFORE / AFTER evidence (screenshot these pairs)
SELECT COUNT(*) AS booking_before FROM MonCity.BOOKING;        -- 10001
SELECT COUNT(*) AS booking_after  FROM BOOKING_C;              -- 10000
SELECT COUNT(*) AS pax_bad_before FROM MonCity.PASSENGER WHERE FACULTYID NOT IN (SELECT FACULTYID FROM MonCity.FACULTY); -- 1
SELECT COUNT(*) AS pax_bad_after  FROM PASSENGER_C       WHERE FACULTYID NOT IN (SELECT FACULTYID FROM MonCity.FACULTY); -- 0
SELECT COUNT(*) AS negcost_before FROM MonCity.MAINTENANCE WHERE MAINTENANCECOST<0;  -- 1
SELECT COUNT(*) AS negcost_after  FROM MAINTENANCE_C       WHERE MAINTENANCECOST<0;  -- 0
SELECT COUNT(*) AS acc_bad_before FROM MonCity.ACCIDENTINFO WHERE ACCIDENTID IS NULL OR ERRORCODE NOT IN (SELECT ERRORCODE FROM MonCity.ERROR); -- 2
SELECT COUNT(*) AS acc_bad_after  FROM ACCIDENTINFO_C       WHERE ACCIDENTID IS NULL OR ERRORCODE NOT IN (SELECT ERRORCODE FROM MonCity.ERROR); -- 0
-- Clean control totals: PASSENGER_C 153 | BOOKING_C 10000 | MAINTENANCE_C 1000 | ACCIDENTINFO_C 992

/* PART 3 — C4: VERSION-1 STAR/SNOWFLAKE IMPLEMENTATION (highest aggregation, natural keys) */
-- 3.1: Dimensions that exist in the (cleaned) source: CTAS

CREATE TABLE FacultyDim AS
SELECT
	*
FROM
	MONCITY.FACULTY;

CREATE TABLE CarDim AS                       
  SELECT
	*
FROM
	MonCity.CAR;
-- body-type roll-up (booking & maintenance)
CREATE TABLE CarBodyDim AS                   
  SELECT
	DISTINCT CARBODYTYPE,
	NUMSEATS
FROM
	MonCity.CAR;

CREATE TABLE MaintenanceTypeDim AS
  SELECT
	*
FROM
	MonCity.MAINTENANCETYPE;

CREATE TABLE ResearchCentreDim AS
  SELECT
	CENTERID,
	CENTERNAME
FROM
	MonCity.RESEARCHCENTER;

CREATE TABLE AccidentZoneDim AS
  SELECT
	DISTINCT ACCIDENTZONE
FROM
	ACCIDENTINFO_C;

CREATE TABLE SeverityDim AS
  SELECT
	DISTINCT CAR_DAMAGE_SEVERITY,
	CASE
		CAR_DAMAGE_SEVERITY WHEN 'No damage' THEN 0
		WHEN 'Very minor damage' THEN 1
		WHEN 'Minor damage' THEN 2
		WHEN 'Moderate damage' THEN 3
		WHEN 'Severe damage' THEN 4
	END AS SEVERITY_RANK
FROM
	ACCIDENTINFO_C;

CREATE TABLE ErrorDim AS
  SELECT
	*
FROM
	MonCity.ERROR;

-- 3.2: TEAM dimension = parent of the M:N; holds GROUPLIST + WEIGHTFACTOR
CREATE TABLE TeamDim AS
  SELECT
	t.TEAMID,
	t.TEAMLEADER,
	(
	SELECT
		LISTAGG(b.CENTERID, '_') WITHIN GROUP (
		ORDER BY b.CENTERID)
	FROM
		MonCity.BELONGTO b
	WHERE
		b.TEAMID = t.TEAMID) AS CENTREGROUPLIST,
	(1 / (
	SELECT
		COUNT(*)
	FROM
		MonCity.BELONGTO b
	WHERE
		b.TEAMID = t.TEAMID)) AS WEIGHTFACTOR
FROM
	MonCity.MAINTENANCETEAM t;

-- 3.3: BRIDGE for the team <-> centre M:N
CREATE TABLE TeamCentreBridge AS
SELECT
	*
FROM
	MonCity.BELONGTO;

-- 3.4: User-defined dimensions (not available in opdb) => Need to CREATE + INSERT
CREATE TABLE MonthDim (MONTHNO NUMBER(2),
MONTHNAME VARCHAR2(10));

INSERT
	INTO
	MonthDim
VALUES (1,
'January');

INSERT
	INTO
	MonthDim
VALUES (2,
'February');

INSERT
	INTO
	MonthDim
VALUES (3,
'March');

INSERT
	INTO
	MonthDim
VALUES (4,
'April');

INSERT
	INTO
	MonthDim
VALUES (5,
'May');

INSERT
	INTO
	MonthDim
VALUES (6,
'June');

INSERT
	INTO
	MonthDim
VALUES (7,
'July');

INSERT
	INTO
	MonthDim
VALUES (8,
'August');

INSERT
	INTO
	MonthDim
VALUES (9,
'September');

INSERT
	INTO
	MonthDim
VALUES (10,
'October');

INSERT
	INTO
	MonthDim
VALUES (11,
'November');

INSERT
	INTO
	MonthDim
VALUES (12,
'December');

CREATE TABLE AgeGroupDim (
    AGEGROUP VARCHAR2(20),
    MIN_AGE  NUMBER(3,0) NOT NULL,
    MAX_AGE  NUMBER (3,0));

INSERT
	INTO
	AgeGroupDim (AGEGROUP,
	MIN_AGE,
	MAX_AGE)
VALUES ('Young adults',
18,
35);

INSERT
	INTO
	AgeGroupDim (AGEGROUP,
	MIN_AGE,
	MAX_AGE)
VALUES ('Middle-aged adults',
36,
59);

INSERT
	INTO
	AgeGroupDim (AGEGROUP,
	MIN_AGE,
	MAX_AGE)
VALUES ('Old-aged adults',
60,
NULL);

-- 3.5: Create Booking Fact via Tempfact table (Month & Age group are user-defined)
CREATE TABLE tempfact_booking AS                        
  SELECT
	p.FACULTYID,
	p.PASSENGERAGE,
	bk.BOOKINGDATE,
	c.CARBODYTYPE
FROM
	BOOKING_C bk
JOIN PASSENGER_C p ON
	p.PASSENGERID = bk.PASSENGERID
JOIN MonCity.CAR c ON
	c.REGISTRATIONNO = bk.REGISTRATIONNO;

ALTER TABLE tempfact_booking ADD (MONTHNO NUMBER(2), AGEGROUP VARCHAR2(20));  

UPDATE tempfact_booking SET MONTHNO = TO_NUMBER(TO_CHAR(BOOKINGDATE,'MM'));
UPDATE
	tempfact_booking t
SET
	AGEGROUP = (
	SELECT
		g.AGEGROUP
	FROM
		AgeGroupDim g
	WHERE
		t.PASSENGERAGE BETWEEN g.MIN_AGE
                             AND NVL(g.MAX_AGE, t.PASSENGERAGE)
);

SELECT * FROM PASSENGER_C pc;

CREATE TABLE BookingFact AS                             
  SELECT
	MONTHNO,
	FACULTYID,
	AGEGROUP,
	CARBODYTYPE,
	COUNT(*) AS NUM_OF_BOOKINGS
FROM
	tempfact_booking
GROUP BY
	MONTHNO,
	FACULTYID,
	AGEGROUP,
	CARBODYTYPE;


-- 3.6: Maintenance & Accident Facts -> built directly (because all dims exist)
CREATE TABLE MaintenanceFact AS
  SELECT
	m.MAINTENANCETYPE,
	c.CARBODYTYPE,
	m.TEAMID,
	COUNT(*) AS NUM_OF_MAINTENANCE,
	SUM(m.MAINTENANCECOST) AS TOTAL_COST
FROM
	MAINTENANCE_C m
JOIN MonCity.CAR c ON
	c.REGISTRATIONNO = m.REGISTRATIONNO
GROUP BY
	m.MAINTENANCETYPE,
	c.CARBODYTYPE,
	m.TEAMID;

CREATE TABLE AccidentFact AS                           
  SELECT
	ca.REGISTRATIONNO,
	a.ACCIDENTZONE,
	a.CAR_DAMAGE_SEVERITY,
	a.ERRORCODE,
	COUNT(*) AS NUM_OF_ACCIDENTS
FROM
	MonCity.CARACCIDENT ca
JOIN ACCIDENTINFO_C a ON
	a.ACCIDENTID = ca.ACCIDENTID
GROUP BY
	ca.REGISTRATIONNO,
	a.ACCIDENTZONE,
	a.CAR_DAMAGE_SEVERITY,
	a.ERRORCODE;

/* PART 4: Verification (every query joins fact + >=1 dimension) */
-- Q1. IT(FIT) faculty, July, by bus                         
SELECT
	SUM(f.NUM_OF_BOOKINGS) AS total_booking_records
FROM
	BookingFact f
JOIN FacultyDim fa ON
	fa.FACULTYID = f.FACULTYID
JOIN MonthDim m ON
	m.MONTHNO = f.MONTHNO
JOIN CarBodyDim b ON
	b.CARBODYTYPE = f.CARBODYTYPE
WHERE
	fa.FACULTYID = 'FIT'
	AND m.MONTHNAME = 'July'
	AND b.CARBODYTYPE = 'Bus';

-- Q2. Calculate booking records by passenger age group 
SELECT
	g.AGEGROUP,
	SUM(f.NUM_OF_BOOKINGS) AS bookings
FROM
	BookingFact f
JOIN AgeGroupDim g ON
	g.AGEGROUP = f.AGEGROUP
GROUP BY
	g.AGEGROUP
ORDER BY
	g.AGEGROUP;

-- Q3. Maintenance records with >=1 team from CE04 (bridge as filter)
SELECT
	SUM(f.NUM_OF_MAINTENANCE) AS maintenance_records
FROM
	MaintenanceFact f
WHERE
	f.TEAMID IN (
	SELECT
		TEAMID
	FROM
		TeamCentreBridge
	WHERE
		CENTERID = 'CE04');

-- Q4. Total cost per maintenance type for mini bus
SELECT
	mt.MAINTENANCETYPE,
	mt.MAINTENANCEDESCRIPTION,
	SUM(f.TOTAL_COST) AS total_cost
FROM
	MaintenanceFact f
JOIN MaintenanceTypeDim mt ON
	mt.MAINTENANCETYPE = f.MAINTENANCETYPE
JOIN CarBodyDim b ON
	b.CARBODYTYPE = f.CARBODYTYPE
WHERE
	b.CARBODYTYPE = 'Mini Bus'
GROUP BY
	mt.MAINTENANCETYPE,
	mt.MAINTENANCEDESCRIPTION
ORDER BY
	mt.MAINTENANCETYPE;

-- Q5. Accidents in ZoneA for Car01
SELECT
	SUM(f.NUM_OF_ACCIDENTS) AS q5
FROM
	AccidentFact f
JOIN CarDim c ON
	c.REGISTRATIONNO = f.REGISTRATIONNO
WHERE
	c.REGISTRATIONNO = 'Car01'
	AND f.ACCIDENTZONE = 'ZoneA';

-- Q6. Accidents per error code at ZoneB for Car06
SELECT
	e.ERRORCODE,
	e.ERRORMESSAGE,
	SUM(f.NUM_OF_ACCIDENTS) AS num_accidents
FROM
	AccidentFact f
JOIN CarDim c ON
	c.REGISTRATIONNO = f.REGISTRATIONNO
JOIN ErrorDim e ON
	e.ERRORCODE = f.ERRORCODE
WHERE
	c.REGISTRATIONNO = 'Car06'
	AND f.ACCIDENTZONE = 'ZoneB'
GROUP BY
	e.ERRORCODE,
	e.ERRORMESSAGE
ORDER BY
	e.ERRORCODE;

-- Q7. Severe-damage accidents on Car05
SELECT
	SUM(f.NUM_OF_ACCIDENTS) AS accidents_on_car05
FROM
	AccidentFact f
JOIN CarDim c ON
	c.REGISTRATIONNO = f.REGISTRATIONNO
WHERE
	c.REGISTRATIONNO = 'Car05'
	AND f.CAR_DAMAGE_SEVERITY = 'Severe damage';

-- Q8 (self-defined): allocated maintenance cost per research centre.
--   WHY USEFUL: a team serves several centres, so raw cost cannot be attributed
--   to one centre. WEIGHTFACTOR (=1/#centres) fairly splits each team's cost across
--  its centres, letting management compare true maintenance burden per centre for
--   budgeting. Grand total is preserved (=302700).

SELECT rc.CENTERID, rc.CENTERNAME,
       ROUND(SUM(f.TOTAL_COST * td.WEIGHTFACTOR),2) AS allocated_cost
FROM   MaintenanceFact f
JOIN   TeamDim td           ON td.TEAMID   = f.TEAMID
JOIN   TeamCentreBridge br  ON br.TEAMID   = f.TEAMID
JOIN   ResearchCentreDim rc ON rc.CENTERID = br.CENTERID
GROUP BY rc.CENTERID, rc.CENTERNAME ORDER BY rc.CENTERID;



SELECT * FROM facultydim;
SELECT * FROM cardim;
SELECT * FROM carbodydim;
SELECT * FROM MAINTENANCETYPEDIM m ;
SELECT * FROM RESEARCHCENTREDIM r ;
SELECT * FROM ACCIDENTZONEDIM a ;
SELECT * FROM SEVERITYDIM s ;
SELECT * FROM errordim;
SELECT * FROM teamdim;
SELECT * FROM monthdim;
SELECT * FROM agegroupdim;
SELECT * FROM BOOKINGFACT b;
SELECT * FROM MAINTENANCEFACT m ;
SELECT * FROM ACCIDENTFACT a ;

