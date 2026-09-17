## Report

**A combined pdf file save as: YourstudentID\_A2\_report.pdf, containing all of the above tasks:**

1. ﻿﻿﻿Cover page  
2. ﻿﻿﻿If you have done the data cleaning process, **explain the strategies** you used in this process (you need to **show the SQL** to explore the operational database and SQL of the data cleaning, as well as **the screenshot of data before and after data cleaning**).  
3. ﻿﻿﻿Two versions of star/snowflake schema diagrams. (You can use Lucidchart or [Draw.io](http://Draw.io) to draw the star schema.)  
4. **﻿﻿﻿Screenshots of the table structure you created for Version-1 only**, including the dimension table and fact tables.  
   *\=\> SQL file for creating the star/snowflake schema is NOT required in submission*

5. Findings report: **A detailed explanation of your findings, including any significant observations / patterns identified during the analysis with sufficient visualisations**

# Tutor guidances: Regarding your question about the level of detail in the visualization, you should consider whether that level of detailed information is actually necessary for the decision being made.

# For example, if the purpose is to help management decide whether to continue investing in the project, this is generally a high-level and long-term decision. Therefore, you should consider whether highly detailed information provides meaningful additional value compared with more highly aggregated data.

# In fact, the final visualisation produced from the two versions — No Aggregation and Highest Aggregation — may be the same for some analyses.

# For example, suppose you want to analyse sales performance by month. If the highest aggregation level is already at the monthly level, the aggregated model can provide the required results directly. With the non-aggregated model, you would first need to aggregate the detailed records to the monthly level before creating the visualisation.

# Therefore, the final monthly sales visualisation could be the same in both cases because the underlying data is the same. The main difference is how the data is modelled and how much additional processing or aggregation is required before the analysis can be performed.

# When deciding what level of detail to retain, you should therefore consider the business purpose of the analysis and whether the additional granularity provides useful information for the management decision.

**1\. Overall submission compliance**  
*Submission status*

* Submit before the deadline.  
* Confirm submission is fully submitted, not left in Draft.  
* If Turnitin shows “File Exceeds the Maximum 100 MB Limit”, this warning itself does not invalidate the submission.  
* Independently verify that Moodle/Turnitin records the submission as completed.

*Backup and technical readiness*

* Keep multiple backups of:  
  * SQL scripts  
  * report  
  * diagrams  
  * Power BI files  
  * screenshots/evidence  
  * presentation/video materials  
* Do not rely on technical issues near the deadline as grounds for an extension.  
* Oracle/VPN/hardware/internet issues should be investigated early.  
* On Mac, do not upgrade to macOS 27 Golden Gate while GlobalProtect incompatibility remains unresolved if VPN access to Oracle is required.  
* Extensions/Special Consideration must go through the **official Monash Special Consideration process**, not teaching staff.

**2\. C1 \- Data Warehouse Requirements**

C1 determines **what the warehouse must contain**.

*Mandatory content*

* Include **all fact measures explicitly required by the assignment**.  
* Include **all dimensions explicitly required by the assignment**.  
* Include the necessary **dimension attributes** for those dimensions.  
* Do **not replace required dimensions or measures with self-defined alternatives**.  
* Do **not introduce additional custom dimensions** merely because they appear analytically useful if they are outside the permitted specification.

*Design reasoning to establish in C1*

Even if the actual schema diagrams appear in C3, your C1 reasoning should make clear:

* What each required measure represents.  
* What its correct business meaning is.  
* Which dimensions provide the analytical context for it.  
* What the intended **grain** of the fact data is.  
* Whether each measure is:  
  * additive,  
  * semi-additive,  
  * or non-additive, where relevant.  
* Why the chosen dimensional information is sufficient for the required analytical questions.

**Critical consistency rule**

- Everything mandatory identified in **C1 must appear correctly in C3**.

Think of the dependency as: **C1 requirements → C3 dimensional model → SQL implementation → analytical outputs**

There should be no disconnect between these stages.

**3\. C2 \- Data Cleaning**

This is one of the sections where tutor expectations are especially explicit.

A. Identify genuinely different data-error types

Do not treat multiple rows with the same problem as multiple distinct cleaning problems.

Example:

> 10 duplicate rows \= **one type of data error**, not 10 separate errors.

Therefore:

* Search for **multiple types of data-quality problems**.  
* Do not stop after identifying duplicates alone.  
* Investigate relevant categories such as:  
  * duplicates  
  * NULL/missing data  
  * invalid domain values  
  * inconsistent formats  
  * inconsistent categorical values  
  * impossible numerical values  
  * logical conflicts between attributes  
  * invalid relationships / referential inconsistencies  
  * data-type or representation problems  
  * business-rule violations

But:

* Do not manufacture “errors” simply to increase the number of cleaning cases.  
* Every claimed error must be defensible within the **MonCity/business/data-warehouse context**.

# **4\. C2 \- Required justification for every identified error**

For **each distinct error**, explicitly answer these three questions.

## **4.1 Why is this an error?**

* State precisely what is wrong.  
* Show the rule, inconsistency, duplication, logical conflict, invalid range, etc.  
* Avoid vague statements such as:  
  * “the data looks incorrect”  
  * “this value should be changed”  
  * “there are duplicates”

Instead explain the actual violation.

Example structure: *These records contain the same business entity and identical defining attributes, therefore they represent duplicate operational records rather than distinct observations.*

## **4.2 Why does it matter to this data warehouse?**

This part is mandatory and should not be reduced to generic “improves data quality”.

For every error, ask:

* Can it create **double counting**?  
* Can it distort fact aggregation?  
* Can it assign facts to the wrong dimension member?  
* Can it create orphan keys?  
* Can it distort age/category/time/location analysis?  
* Can it make joins unreliable?  
* Can it cause incorrect Power BI totals?  
* Can it compromise historical or dimensional consistency?

Your justification should connect the OPDB error to its **downstream warehouse consequence**.

## **4.3 Why is your correction method appropriate?**

For each correction:

* State exactly how the data was corrected.  
* Explain **why that method was selected**.  
* Explain why it preserves more valid information than alternative approaches where relevant.  
* Ensure the correction follows a defensible business/data rule.

Do not assume deletion is automatically valid.

# **5\. C2 \- Do not default to deleting erroneous records**

Tutor guidance is explicit: Deletion is not automatically the correct solution.

Before using DELETE, check:

* Is the record completely unusable?  
* Can the correct value be derived from another attribute?  
* Can it be standardised?  
* Can it be transformed?  
* Can it be reconciled with another valid record?  
* Would deleting it remove valid business information?  
* Would deletion disproportionately reduce the dataset?  
* Could deletion even wipe out a large part of a table?

Prefer correction/transformation when it preserves valid information.

Use deletion only where there is a strong justification, such as:

* a true redundant duplicate,  
* irrecoverably invalid record,  
* or record that demonstrably should not represent a business entity/event.

# **6\. C2 \- Mandatory evidence package for every error**

For **each identified error**, include all three SQL stages.

## **Stage 1 \- Detection SQL**

* Include the SQL query used to identify/demonstrate the problem.  
* Include this SQL as **text in the report**.

Example purpose:

SELECT ...  
FROM ...  
WHERE ...;

## **Stage 2 \- Cleaning SQL**

* Include the actual SQL used to correct the problem.  
* This might be:  
  * UPDATE  
  * DELETE  
  * transformation  
  * standardisation  
  * duplicate removal  
  * another appropriate operation  
* Include this SQL as **text in the report**.

## **Stage 3 \- Verification SQL**

* Re-run an appropriate query after cleaning.  
* Demonstrate that the error has actually been resolved.  
* Include the verification SQL where relevant.

The logic should be visibly auditable:

**Detect → Correct → Verify**

# **7\. C2 \- Screenshot requirements**

Tutor guidance requires screenshots, not SQL text alone.

## **Before cleaning screenshot**

For each error:

* Screenshot must show the **SQL query used to identify/demonstrate the error**.  
* Screenshot must show the **query result containing evidence of the error**.  
* Error must be visibly identifiable from the result.

Examples:

* duplicate rows visible,  
* NULL values visible,  
* invalid/inconsistent values visible,  
* impossible value visible.

## **After cleaning screenshot**

* Show evidence that the cleaning has worked.  
* Depending on the case, this could show:  
  * zero duplicate records,  
  * corrected value,  
  * standardised values,  
  * empty result set from the original error-detection query,  
  * successful valid relationship.

The examiner should be able to see:

> **Before: error exists → Cleaning SQL applied → After: error no longer exists**

without having to infer what happened.

# **8\. C2 \- Do not include irrelevant “no-error” exploration**

Tutor explicitly says:

> Queries that return no errors do not need to be included.

Therefore:

* You may perform extensive exploratory SQL privately.  
* Do **not fill the report with queries that found nothing**.  
* Only include exploration SQL that actually demonstrates a relevant identified error.  
* Focus report space on evidence, decisions, correction and validation.

This is important for report quality: **completeness does not mean dumping every SQL check**.

# **9\. Recommended C2 reporting structure**

For every error, use the same structure:

### **Error X \- \[Descriptive error name\]**

**Detection / Evidence**

* What is wrong?  
* Why is it an error?  
* Detection SQL  
* Before screenshot

**Warehouse relevance**

* What would happen if this were loaded unchanged?  
* Which measure/dimension/analysis could be affected?

**Correction**

* Cleaning SQL  
* Why this method is appropriate  
* Why deletion/transformation/etc. is justified

**Verification**

* Verification SQL  
* After screenshot  
* Short statement confirming the problem has been resolved

This structure maps almost exactly to tutor expectations and makes the section easy to mark.

# **10\. C3 \- Star / Snowflake Schema Design**

C3 is where the actual warehouse schema is **designed and presented**.

## **Mandatory consistency with C1**

* Every required fact measure from C1 appears in the relevant fact table.  
* Every required dimension from C1 appears.  
* Required dimension attributes are available.  
* Schemas can answer the analytical questions specified in C3.

C3 is **not independent from C1**.

The model must satisfy both:

> **Mandatory warehouse requirements from C1**

and

> **Analytical requirements/questions in C3**

# **11\. C3 \- Define the grain before modelling relationships**

Before freezing each fact table, write a one-sentence grain declaration:

> “One row in FactX represents …”

Then check:

* Every measure is valid at this grain.  
* Every dimension key refers to an entity meaningful at this grain.  
* No dimension relationship accidentally changes the grain.  
* There is no hidden many-to-many relationship creating fact multiplication.  
* Aggregating the fact rows does not produce double counting.

This is one of the most important checks because the tutor explicitly highlights:

* correct aggregation level  
* avoiding double counting  
* avoiding modelling errors  
* avoiding unnecessary/inefficient design.

# **12\. C3 \- Double-counting audit**

For every fact table, ask:

### **If I join every associated dimension, can one fact row become multiple rows?**

If yes:

* Investigate the relationship before finalising the schema.

Particularly inspect:

* M:N relationships  
* bridge tables  
* multi-valued dimensions  
* repeated dimension records  
* fact-to-fact joins  
* inappropriate snowflaking  
* duplicated natural keys

You should be able to explain why:

SUM(measure)\\text{SUM(measure)}

remains semantically valid after dimensional joins.

# **13\. C3 \- Aggregation-level audit**

For every required measure:

* Identify its native grain.  
* Confirm it is stored at the correct fact grain.  
* Confirm higher-level summaries can be derived correctly.  
* Avoid pre-aggregating so far that required analysis becomes impossible.  
* Avoid storing unnecessarily detailed structures when the assignment requires higher aggregation.

A high-quality schema is not simply the “most detailed possible” one.

It should be the **appropriate dimensional representation for the required analytical grain**.

---

# **14\. C3 \- Relationship audit**

For every relationship shown in the diagram:

* Cardinality is correct.  
* PK/FK direction is correct.  
* Surrogate keys are used consistently where required.  
* Fact-to-dimension relationship is logically valid.  
* Any bridge table has a genuine business need.  
* M:N relationships are not accidentally implemented as 1:M.  
* No unnecessary direct dimension-to-dimension relationship is introduced.  
* No cyclic paths create ambiguous analysis.  
* The design supports correct SQL joins and Power BI relationships.

---

# **15\. C3 \- Star vs snowflake decisions**

Do not snowflake simply to make the design appear sophisticated.

For each normalised dimension structure ask:

* Does the snowflake structure reflect a legitimate hierarchy/business entity?  
* Does it improve integrity or eliminate meaningful redundancy?  
* Does it preserve analytical simplicity?  
* Is it actually required by the problem?

Likewise, do not force everything into a flat star if this introduces incorrect relationships.

The criterion is:

> **Correctness \+ analytical usefulness \+ efficient dimensional modelling**

not visual complexity.

---

# **16\. Additional dimensions / measures**

Tutor guidance is strict:

* Use the fact measures and dimensions required by the assignment.  
* Do not create your own replacement dimensional model.  
* Do not introduce custom dimensions merely to extend the analysis unless explicitly permitted.  
* Do not omit required dimensions because another design appears more elegant.

Any enhancement must remain inside the stated assignment constraints.

---

# **17\. Diagram quality checklist**

For every C3 schema diagram:

* Fact table clearly identifiable.  
* Dimension tables clearly identifiable.  
* PKs shown.  
* FKs shown.  
* Measures clearly distinguished.  
* Required attributes shown.  
* Cardinality visible.  
* Bridge tables clearly identified where applicable.  
* No ambiguous lines.  
* No orphan dimensions.  
* No duplicated relationships.  
* Table/attribute naming matches SQL implementation.  
* Diagram reflects the **final script**, not an earlier design.  
* Diagram is readable at report scale.

Most importantly:

> **Diagram, SQL script and explanation must describe exactly the same warehouse.**

---

# **18\. Cross-section consistency audit**

Before submission, create a traceability check:

| Requirement | C1 | C3 Diagram | SQL Implementation | Power BI/Analysis |
| ----- | ----- | ----- | ----- | ----- |
| Fact measure 1 | ✓ | ✓ | ✓ | ✓ |
| Fact measure 2 | ✓ | ✓ | ✓ | ✓ |
| Dimension A | ✓ | ✓ | ✓ | ✓ |
| Dimension B | ✓ | ✓ | ✓ | ✓ |
| Required analytical question | ✓ | Supported | Supported | Answered |

If any row contains:

**✓ → missing → different name → different grain**

then the assignment is internally inconsistent.

---

# **19\. SQL implementation quality**

Even though the FAQ excerpt focuses primarily on C1-C3, the implementation should be checked against the conceptual model.

* Table definitions match diagrams.  
* Datatypes are appropriate.  
* PK constraints are correct.  
* FK constraints are correct.  
* NOT NULL constraints are used where logically required.  
* CHECK constraints implement relevant business/domain rules.  
* Dimension loading logic avoids duplicate members.  
* Fact loading occurs only after required dimensions are available.  
* Surrogate-key lookup is deterministic.  
* Unknown/missing dimension handling is consistent.  
* Measures are loaded at exactly the declared grain.  
* Re-running scripts does not silently create duplicate fact rows where avoidable.

---

# **20\. Power BI / analytical output quality**

Since the dimensional model is intended for analytics:

* Power BI uses the final warehouse structure.  
* Relationships reflect the designed schema.  
* Fact tables are not connected in a way that causes ambiguous filtering.  
* Measures aggregate correctly.  
* Dashboard results answer the specified analytical questions.  
* No visual relies on a relationship inconsistent with the submitted C3 model.  
* Verify key totals against SQL independently.

A strong final validation is:

> Choose several important Power BI totals and reproduce them directly in SQL.

If SQL and Power BI disagree, investigate before submission.

---

# **21\. Video presentation**

You may present using either:

* the report, or  
* PowerPoint slides.

Slides are **optional**.

If slides are used:

* Content is fully consistent with the submitted report.  
* Do not introduce a different schema or revised result that is absent from the submitted report.  
* Five-minute limit is respected.  
* Focus on the important reasoning rather than reading implementation code line-by-line.

A sensible five-minute narrative is:

**Problem/requirements → data-quality decisions → dimensional design → key implementation choices → analytical outcome**

---

# **22\. Report quality \- what the examiner should be able to verify**

For every important modelling/cleaning decision, the report should answer:

### **What?**

What did you identify/design?

### **Why?**

Why is it correct for this business problem?

### **Impact?**

What would go wrong if it were not handled correctly?

### **How?**

How did you implement the solution?

### **Evidence?**

What SQL, screenshot, diagram or output proves it?

This is much stronger than simply documenting steps.

---

# **23\. Things to avoid**

Do **not**:

* Count 10 duplicate rows as 10 separate error types.  
* Stop data cleaning after checking duplicates.  
* Delete invalid data automatically without evaluating alternatives.  
* Include pages of queries that found no problems.  
* Show “before” screenshots without the detecting SQL.  
* Show “after” screenshots without evidence that the error is resolved.  
* Claim something is an error without explaining why.  
* Explain cleaning only from an OPDB perspective without discussing warehouse consequences.  
* Design C3 independently of C1.  
* Add arbitrary custom dimensions/measures.  
* Create a sophisticated-looking schema that introduces double counting.  
* Use incorrect grain merely to simplify the diagram.  
* Let diagrams and SQL implementation drift apart.  
* Let Power BI relationships contradict the submitted schema.  
* Leave submission in Draft status.

---

# **24\. Final “freeze” audit before submission**

I would only consider the assignment design frozen once all of these are true:

### **Data quality**

* Every reported error is real and evidenced.  
* Multiple meaningful error types have been investigated.  
* Every cleaning decision has the required three-part justification.  
* Detection SQL \+ cleaning SQL \+ verification SQL are included.  
* Required before/after screenshots are included.

### **Dimensional modelling**

* C1 mandatory requirements are fully represented in C3.  
* Every fact table has an explicit grain.  
* Every measure is valid at that grain.  
* Cardinalities are correct.  
* M:N relationships are handled correctly.  
* No double-counting path exists.  
* No unnecessary dimensions/tables exist.  
* Required analytical questions are answerable.

### **Implementation**

* SQL matches diagrams exactly.  
* Keys and constraints are correct.  
* ETL/loading logic preserves grain.  
* Dimensions and facts contain expected row counts.  
* Aggregates have been independently sanity-checked.

### **Analytics**

* Power BI relationships match the warehouse model.  
* Analytical questions can actually be answered.  
* SQL and Power BI key totals agree.

### **Submission**

* Report finalised.  
* SQL finalised.  
* Diagrams finalised.  
* Screenshots readable.  
* Video consistent with report.  
* Backup exists.  
* Submission is complete rather than Draft.

## **Core tutor expectations in one sentence**

The strongest way to interpret the FAQ is:

> **Do not merely show that the assignment “works”; demonstrate that each data-cleaning and dimensional-modelling decision is logically necessary, correctly implemented, evidenced in SQL/results, aligned with the prescribed requirements, and safe from aggregation, grain and double-counting errors.**

For your current **MonCity 5137** work, this means the next most important freeze check is the chain **C1 required dimensions/measures → C3 grain/cardinality/bridge design → C4 SQL implementation → Power BI aggregation behaviour**, because a modelling error in that chain can propagate even when each individual SQL statement executes successfully.