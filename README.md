# Semantic Data Integration Across Multi-Source Warehouses via Star/Snowflake Schema Design with Dimensional Modeling

**Domain Application:** University Enterprise Data Warehouse Consolidation  
**Subject:** Data Mining & Warehousing  
**Project Guide / Mentor:** Mr. S. V. Swamy  

---

## 1. Executive Summary & Abstract

Modern educational institutions maintain disconnected, siloed operational systems—ranging from Admissions Portals and Student Information Systems (SIS) to Learning Management Systems (LMS / Moodle), Fee/Finance Accounting, and Library Automation Systems. Each transactional source operates on disparate database engines, data formats, identifier conventions, and update frequencies.

This project designs and implements an **Enterprise Data Warehouse (EDW)** utilizing **Kimball Dimensional Modeling**, comparing and combining **Star and Snowflake Schemas** to deliver unified analytical intelligence. By introducing a **Semantic Data Integration Layer**, heterogeneous source entities are reconciled, resolving schema ambiguities, conflicting naming standards, and data quality inconsistencies. The resulting consolidated repository provides a holistic "Student 360°" analytical view, empowering university administration to track academic progression, optimize retention, identify at-risk students, audit departmental finances, and enhance resource utilization.

---

## 2. Source Systems Profile & Semantic Challenges

| Source System | Typical Technology | Key Entities Extracted | Semantic Heterogeneity Challenges |
| :--- | :--- | :--- | :--- |
| **Admissions System** | MySQL / Web Portal | Applicant, Application, Test Scores, Allotment | Pre-enrollment ID (`APP_NO`); different status strings (`'ACCEPTED'`, `'JOINED'`). |
| **Student Information System (SIS)** | Oracle / SQL Server | Student Master, Enrollment, Course, Major, Faculty | Enrolled Student ID (`REG_NO` / `ROLL_NO`); separate department taxonomy. |
| **LMS (e.g. Moodle / Canvas)** | PostgreSQL / NoSQL | User, Course Module, Quiz Attempt, Forum Post, Submission | Username is email (`user@univ.edu`); timestamps in UTC epoch; granular clickstream logs. |
| **Fee & Finance System** | Proprietary ERP | Invoice, Payment, Dues, Scholarship, Fee Category | Student identified by admission reference; monetary amounts stored with varying tax/discount flags. |
| **Library Automation (Koha)** | MariaDB | Patron, Book Checkout, Returns, Fines, Catalog | Barcode identifier; patron categories (`'UG'`, `'PG'`, `'RS'`) misaligned with academic terms. |

### Semantic Reconciliation Techniques
1. **Entity Resolution & Unified Master Index:** Linking `APP_NO`, `REG_NO`, and LMS `username/email` into a single conformed `student_key` surrogate key.
2. **Conformed Dimensions:** Standardizing temporal grains (`dim_date`, `dim_semester`), organizational units (`dim_department`), and academic offerings (`dim_course`).
3. **Snowflaking vs. Pure Star Selection:**
   - **Star Schema** is applied to high-query-velocity facts (`fact_course_enrollment_grades`, `fact_fee_transactions`, `fact_lms_activity`) for maximum OLAP aggregation speed and minimal joins.
   - **Snowflake Schema** is selectively applied to deep, normalized hierarchies such as `dim_student -> dim_major_program -> dim_department -> dim_faculty_college` and `dim_course -> dim_subject_area -> dim_department` to eliminate redundant descriptive strings and preserve strict administrative normalization.

---

## 3. Dimensional Bus Matrix

The Kimball Dimensional Bus Matrix maps business processes (Fact Tables) across Conformed Dimensions:

| Business Process (Fact Table) | Date / Term | Student | Course / Module | Instructor / Faculty | Department | Fee Category | Library Asset |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Student Admissions (`fact_student_admissions`)** | **X** | **X** (Applicant) | - | - | **X** | - | - |
| **Academic Performance (`fact_course_enrollment_grades`)** | **X** | **X** | **X** | **X** | **X** | - | - |
| **LMS Engagement (`fact_lms_activity`)** | **X** | **X** | **X** | - | - | - | - |
| **Fee Collection & Dues (`fact_fee_transactions`)** | **X** | **X** | - | - | **X** | **X** | - |
| **Library Circulation (`fact_library_circulation`)** | **X** | **X** | - | - | **X** | - | **X** |
| **Student 360 Periodic Snapshot (`fact_student_academic_360_monthly`)** | **X** | **X** | - | - | **X** | - | - |

---

## 4. Repository Structure & Scripts

```text
university_dw_consolidation/
├── README.md                           # Comprehensive documentation & architectural overview
├── 01_schema_ddl.sql                   # Staging, Conformed Dimensions, Star/Snowflake Facts DDL
├── 02_sample_data.sql                  # Heterogeneous multi-source mock data with real-world anomalies
├── 03_semantic_etl_pipeline.sql        # Semantic mapping, deduplication, surrogate key generation & ELT
├── 04_olap_analytical_queries.sql      # Roll-up, drill-down, slice-and-dice, and Student 360 KPIs
└── PROJECT_REPORT_DRAFT.md             # Complete academic dissertation/report chapter draft
```

---

## 5. Execution Instructions (PostgreSQL / ANSI SQL)

1. Open your SQL client (e.g. pgAdmin, DBeaver, psql, or any standard SQL IDE).
2. Execute `01_schema_ddl.sql` to establish `staging`, `edw_dim`, and `edw_fact` schemas.
3. Run `02_sample_data.sql` to populate multi-source operational tables.
4. Execute `03_semantic_etl_pipeline.sql` to run the semantic integration, entity resolution, and dimensional loading.
5. Execute `04_olap_analytical_queries.sql` to view multi-dimensional analytical reports and early-warning dropout risk scoring.
