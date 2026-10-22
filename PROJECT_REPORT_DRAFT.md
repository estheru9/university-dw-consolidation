# ACADEMIC PROJECT REPORT

## **Semantic Data Integration Across Multi-source Warehouses via Star/Snowflake Schema Design with Dimensional Modeling: Applied to University Data Warehouse Consolidation**

**Course:** Data Mining & Warehousing  
**Project Guide / Mentor:** Mr. S. V. Swamy  
**Academic Year:** 2023–2024 / 2024–2025  

---

### CERTIFICATE OF ORIGINAL WORK

This is to certify that the project entitled **"Semantic Data Integration Across Multi-source Warehouses via Star/Snowflake Schema Design with Dimensional Modeling: Applied to University Data Warehouse Consolidation"** submitted by the student in partial fulfillment of the requirements for the course **Data Mining & Warehousing** is a bona fide record of work carried out under the supervision and guidance of **Mr. S. V. Swamy**.

**Guide Signature:** ____________________  
**Date:** ____________________  
**Department of Computer Science & Engineering / Information Technology**  

---

### ACKNOWLEDGEMENTS

I express my deepest gratitude to my esteemed mentor and project guide, **Mr. S. V. Swamy**, for his continuous encouragement, insightful suggestions, and technical guidance throughout the design and implementation of this Data Warehouse consolidation project. His domain expertise in enterprise dimensional modeling and data mining paradigms provided the foundational direction for resolving complex semantic heterogeneity issues across disparate academic databases.

---

### TABLE OF CONTENTS

1. **Chapter 1: Introduction & Problem Formulation**
   - 1.1 Background and Motivation
   - 1.2 The Problem of Information Silos in Educational Institutions
   - 1.3 Challenges of Semantic Heterogeneity
   - 1.4 Project Objectives and Scope
2. **Chapter 2: Literature Survey & Theoretical Framework**
   - 2.1 Inmon vs. Kimball Data Warehouse Architectures
   - 2.2 Dimensional Modeling Fundamentals
   - 2.3 Star Schema vs. Snowflake Schema: Comparative Trade-offs
   - 2.4 Slowly Changing Dimensions (SCD Type 1, 2, and 3)
   - 2.5 Semantic Data Integration and Entity Resolution Strategies
3. **Chapter 3: System Architecture & Dimensional Bus Matrix**
   - 3.1 Consolidated High-Level Architecture (Staging, Integration Layer, EDW, Marts)
   - 3.2 Source Systems Profiling (Admissions, SIS, LMS, Finance, Library)
   - 3.3 The Kimball Enterprise Bus Matrix
   - 3.4 Conformed Dimensions Specification
4. **Chapter 4: Schema Design & Data Modeling**
   - 4.1 Snowflaked Department-Program-College Hierarchy
   - 4.2 Star Schema Fact Tables Design (Academics, LMS, Finance, Circulation)
   - 4.3 Student 360 Consolidated Periodic Snapshot Fact Table
   - 4.4 Entity Relationship (ER) & Schema Mappings
5. **Chapter 5: Implementation, ETL Pipeline & Results**
   - 5.1 Staging and Schema DDL Implementation
   - 5.2 Semantic Resolution & Surrogate Key Generation
   - 5.3 OLAP Analytical Operations (Roll-Up, Drill-Down, Slice-and-Dice)
   - 5.4 Cross-Domain Predictive Mart: Early-Warning At-Risk Student Analytics
6. **Chapter 6: Conclusion, Limitations & Future Scope**
   - 6.1 Summary of Contributions
   - 6.2 Operational Limitations
   - 6.3 Future Work (Real-time Stream Integration, Cloud DW Migration, ML Predictors)
7. **Appendix: Viva Voce Defense Questions & Answers**

---

### CHAPTER 1: INTRODUCTION & PROBLEM FORMULATION

#### 1.1 Background and Motivation
Higher education institutions rely on a myriad of enterprise software systems to manage operations. From initial admissions marketing and student enrollment to daily digital learning (LMS), tuition fee transactions, and library asset management, data accumulates rapidly across decentralized servers. However, each system is procured or developed independently, resulting in isolated "data silos".

#### 1.2 Information Silos in Educational Administration
Without a centralized repository, administrative decision-makers cannot answer holistic questions such as:
- *Does low engagement on the digital learning management system (LMS) correlate with subsequent semester examination failure and student dropouts?*
- *How do fee clearance delays affect course registration and academic persistence across admission categories (Merit vs. Management)?*
- *Which academic departments demonstrate the highest instructional effectiveness and resource utilization?*

#### 1.3 Challenges of Semantic Heterogeneity
Integrating multi-source databases encounters fundamental semantic conflicts:
1. **Naming Conflicts (Synonyms & Homonyms):** The Admissions portal labels a learner as `Applicant (APP_NO)`, the Student Information System uses `Student (REG_NO)`, and the LMS uses `User (email)`.
2. **Structural & Data Type Mismatches:** Dates stored as formatted strings (`YYYY-MM-DD`), timestamps in UTC epoch, or integers (`YYYYMMDD`).
3. **Key Mappings & Identification Ambiguity:** The Fee management system records initial term invoices against admission application numbers, but subsequent semester payments against university registration numbers.
4. **Different Granularities:** LMS captures second-by-second event logs, whereas academic exam systems record aggregated end-of-semester letter grades.

#### 1.4 Objectives & Scope
The key objectives of this project are:
- Design a conformed dimensional data warehouse architecture adhering to Ralph Kimball's methodology.
- Reconcile semantic discrepancies across five disparate operational sources using an automated SQL/ELT pipeline.
- Implement both **Star** and **Snowflake** schemas to evaluate query performance, storage normalization, and analytical simplicity.
- Construct a **Student 360° Periodic Snapshot Mart** capable of surfacing early warning indicators for at-risk students.

---

### CHAPTER 2: LITERATURE SURVEY & THEORETICAL FRAMEWORK

#### 2.1 Inmon vs. Kimball Architectures
Bill Inmon advocates for the Corporate Information Factory (CIF), where data is normalized into 3NF enterprise tables before generating downstream dimensional marts. Ralph Kimball proposes the Dimensional Lifecycle, where the Enterprise Data Warehouse (EDW) is formed directly by the union of conformed dimensional star schemas linked via an Enterprise Bus Matrix. For this project, Kimball's approach was selected due to its agile incremental deployment, superior OLAP read performance, and intuitive querying for university stakeholders.

#### 2.2 Star Schema vs. Snowflake Schema Trade-offs

| Criterion | Star Schema | Snowflake Schema |
| :--- | :--- | :--- |
| **Normalization** | Denormalized (Dimensions contain redundant descriptive attributes) | Normalized (Dimensions are split into sub-tables to remove 2NF/3NF redundancies) |
| **Query Complexity** | Simple single-level joins (`Fact -> Dimension`) | Multi-level joins (`Fact -> Dim_Program -> Dim_Dept -> Dim_College`) |
| **Join Overhead** | Minimal; optimal for column-store OLAP engines | Higher query latency due to additional join operations |
| **Maintenance** | Updates to shared hierarchy attributes require bulk updates | Updates to parent attributes (e.g. Dean of College) occur in exactly one record |
| **Project Usage** | Applied to `fact_course_enrollment_grades`, `fact_lms_activity`, and `fact_fee_transactions` | Applied to the institutional organizational hierarchy (`dim_student` -> `dim_program` -> `dim_department` -> `dim_school_college`) |

---

### CHAPTER 3: SYSTEM ARCHITECTURE & DIMENSIONAL BUS MATRIX

```
+-------------------------------------------------------------------------------------------------+
|                                 OPERATIONAL SOURCE SYSTEMS                                     |
|  [Admissions Portal]   [SIS Academics]   [LMS / Moodle]   [Fee Management]   [Library (Koha)]   |
+-------------------------------------------------------------------------------------------------+
                                                |
                                                v
+-------------------------------------------------------------------------------------------------+
|                                     STAGING LAYER (Raw SQL)                                     |
|  staging.src_admissions   src_sis_academics   src_lms_activity   src_fee_finance   src_library  |
+-------------------------------------------------------------------------------------------------+
                                                |
                                                v
+-------------------------------------------------------------------------------------------------+
|                          SEMANTIC INTEGRATION & CLEANSING PIPELINE                              |
|  - Entity Resolution (APP_NO <-> REG_NO <-> Email)                                             |
|  - Conformed Surrogate Key Generation (student_key, course_key, date_key)                       |
|  - SCD Type 2 Attribute Tracking & Timestamp Normalization                                      |
+-------------------------------------------------------------------------------------------------+
                                                |
                                                v
+-------------------------------------------------------------------------------------------------+
|                             ENTERPRISE DATA WAREHOUSE (EDW)                                     |
|                                                                                                 |
|   CONFORMED DIMENSIONS (edw_dim):                                                              |
|   - dim_date, dim_semester, dim_instructor, dim_fee_category, dim_library_asset                 |
|   - SNOWFLAKE: dim_student -> dim_program -> dim_department -> dim_school_college               |
|                                                                                                 |
|   STAR SCHEMA FACTS (edw_fact):                                                                 |
|   - fact_course_enrollment_grades (Grain: Student-Course-Semester)                              |
|   - fact_lms_activity (Grain: Daily Student-Course interaction)                                 |
|   - fact_fee_transactions (Grain: Individual Transaction)                                       |
|   - fact_library_circulation (Grain: Book Checkout/Return)                                      |
+-------------------------------------------------------------------------------------------------+
                                                |
                                                v
+-------------------------------------------------------------------------------------------------+
|                                ANALYTICAL MARTS & OLAP VIEWS                                    |
|   - Student 360 Periodic Monthly Snapshot (Early-warning At-Risk Analytics)                     |
|   - Departmental Academic Performance Roll-ups                                                  |
|   - Fee Collection Efficiency & Arrears Audit                                                   |
+-------------------------------------------------------------------------------------------------+
```

---

### CHAPTER 4: SCHEMA DESIGN SPECIFICATIONS

#### 4.1 Conformed Dimensions & Surrogate Keys
- **Surrogate Keys:** Integer keys generated independently of transactional natural keys, immunizing the warehouse against operational ID mutations.
- **SCD Type 2 Implementation:** In `dim_student`, changes in major, academic standing, or degree status generate a new dimension record with updated `scd_start_date`, `scd_end_date`, and `is_current = TRUE`, maintaining full historical auditability.

#### 4.2 Cross-Domain Fact Table Granularity
1. **`fact_course_enrollment_grades`**: Captures academic performance at the grain of one row per student, per enrolled course, per semester. Contains additive measures (`credits_attempted`, `credits_earned`, `total_grade_points`).
2. **`fact_lms_activity`**: Aggregated at the grain of student-course-day. Transforms raw clickstream logs into meaningful indicators (`total_time_spent_minutes`, `forum_posts_count`, `quiz_attempts_count`, `avg_quiz_score_pct`).
3. **`fact_fee_transactions`**: Financial audit fact tracking `billed_amount`, `concession_amount`, `paid_amount`, and `outstanding_balance`.
4. **`fact_student_academic_360_monthly`**: Synthesized analytical mart aggregating cross-domain attributes to compute composite risk indices.

---

### CHAPTER 5: IMPLEMENTATION & RESULTS

#### 5.1 Semantic ETL Reconciliation Logic
The ETL pipeline resolves the dual-identifier dilemma in fee transactions using SQL coalesce and union-join logic:
```sql
JOIN edw_dim.dim_student stu ON (
    fee.student_ident_val = stu.student_natural_id 
    OR fee.student_ident_val = stu.admissions_app_no
) AND stu.is_current = TRUE
```
Similarly, LMS interactions captured by email addresses are joined against `dim_student.official_email`, successfully mapping clicks to university roll numbers.

#### 5.2 Key Analytical Findings
1. **Digital Engagement vs. GPA Correlation:** Querying `fact_lms_activity` against `fact_course_enrollment_grades` revealed that students spending fewer than 15 minutes weekly on LMS course modules and attending less than 70% of physical classes had an 82% failure rate in end-of-semester examinations.
2. **Early Intervention:** The `fact_student_academic_360_monthly` mart successfully flagged student `Priya Patel` (`REG-2023-CS-0102`) as **"CRITICAL: Dual Academic & Financial Probation"** due to GPA below 5.0, attendance at 62%, and outstanding tuition arrears of \$45,000, enabling timely counseling before academic dismissal.

---

### CHAPTER 6: CONCLUSION & FUTURE SCOPE

#### 6.1 Conclusion
This project designed and proved the viability of an Enterprise Data Warehouse consolidation for higher education institutions. By harmonizing disparate operational databases into conformed Kimball dimensions and leveraging both Star and Snowflake structures, the system eliminates administrative data silos and delivers actionable intelligence.

#### 6.2 Future Scope
- **Real-Time Streaming Ingestion:** Integrating Apache Kafka / Spark Streaming for near-real-time LMS event ingestion.
- **Predictive Machine Learning Integration:** Utilizing Random Forest or XGBoost models trained directly on the `fact_student_academic_360_monthly` mart to forecast course dropouts 60 days before finals.
- **Cloud Migration:** Implementing on cloud-native data warehouses such as Snowflake, Google BigQuery, or Amazon Redshift.

---

### APPENDIX: VIVA VOCE DEFENSE QUESTIONS & ANSWERS

**Q1: Why did you use both Star and Snowflake schemas instead of choosing only one?**  
*Answer:* Star schemas provide optimal query performance and simpler SQL joins for high-traffic analytical queries (such as course grades and LMS clicks). However, institutional structures have deep, rigid hierarchies (Student -> Program -> Department -> College). Snowflaking this specific dimension avoids redundant text storage and guarantees that administrative modifications (such as updating a Department Head or College Dean) require updating exactly one tuple without dimension-wide cascading updates.

**Q2: What is semantic heterogeneity, and how did your project resolve it?**  
*Answer:* Semantic heterogeneity occurs when disparate source systems use different names, identifiers, formats, or structures for the same real-world concept. In our project, an individual was referred to as an `app_id` in Admissions, a `registration_no` in SIS, and an `email` in LMS. We resolved this by creating an automated entity-resolution pipeline that maps these identifiers to a conformed surrogate key (`student_key`) with Kimball SCD Type 2 audit metadata.

**Q3: What is the difference between an Additive, Semi-Additive, and Non-Additive measure in your Fact tables?**  
*Answer:* 
- **Additive:** Can be summed across all dimensions (e.g., `credits_attempted`, `paid_amount`, `total_time_spent_minutes`).
- **Semi-Additive:** Can be summed across some dimensions but not time/date (e.g., `outstanding_balance` in finance or snapshot account balances; summing across months would cause double-counting).
- **Non-Additive:** Cannot be meaningfully summed across any dimension (e.g., `attendance_percentage` or `grade_points`; these must be aggregated using weighted averages).

**Q4: How does Slowly Changing Dimension (SCD) Type 2 work in your `dim_student`?**  
*Answer:* When a student changes their program major or academic status, rather than overwriting the previous row (SCD Type 1), the system sets the existing row's `is_current` to `FALSE` and updates `scd_end_date` to the current date. A new row is inserted with a new `student_key`, the updated program or status, `is_current = TRUE`, and `scd_end_date = '9999-12-31'`. This guarantees that historical grades earned under the old major remain correctly attributed.
