-- ============================================================================
-- SCRIPT 01: SCHEMA DDL DEFINITION
-- Project: Semantic Data Integration Across Multi-source Warehouses
-- Domain: University Data Warehouse Consolidation
-- Target Engine: ANSI SQL / PostgreSQL Compatible
-- Guide / Mentor: Mr. S. V. Swamy
-- ============================================================================

-- Create isolated logical namespaces / schemas
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS edw_dim;
CREATE SCHEMA IF NOT EXISTS edw_fact;

-- ============================================================================
-- 1. STAGING LAYER: HETEROGENEOUS SOURCE SYSTEM EXTRACTS
-- ============================================================================

-- Source 1: Admissions Portal (MySQL OLTP source)
DROP TABLE IF EXISTS staging.src_admissions CASCADE;
CREATE TABLE staging.src_admissions (
    app_id VARCHAR(50),
    candidate_name VARCHAR(150),
    applicant_email VARCHAR(150),
    phone_no VARCHAR(25),
    allocated_branch_code VARCHAR(30),
    entrance_exam_rank INT,
    admission_category VARCHAR(50), -- e.g., 'Merit', 'Management', 'Quota'
    admission_status VARCHAR(50),   -- e.g., 'ACCEPTED', 'CONFIRMED', 'WITHDRAWN'
    allotment_date VARCHAR(30),     -- Unformatted string date e.g., '2023-06-15'
    application_fee_paid NUMERIC(10, 2)
);

-- Source 2: Student Information System / SIS (Oracle/SQL Server OLTP)
DROP TABLE IF EXISTS staging.src_sis_academics CASCADE;
CREATE TABLE staging.src_sis_academics (
    enrollment_no VARCHAR(50),      -- e.g., 'REG-2023-CS-0101'
    admissions_ref_no VARCHAR(50),  -- Pointer back to app_id
    full_name VARCHAR(150),
    official_email VARCHAR(150),
    program_id VARCHAR(50),         -- e.g., 'BTECH_CSE'
    department_name VARCHAR(100),
    academic_term VARCHAR(50),      -- e.g., '2023-Fall', '2024-Spring'
    course_code VARCHAR(50),        -- e.g., 'CS301'
    course_title VARCHAR(150),
    instructor_emp_id VARCHAR(50),
    instructor_name VARCHAR(150),
    credits INT,
    grade_letter VARCHAR(5),        -- 'A+', 'B', 'C', 'F'
    grade_points NUMERIC(4, 2),     -- 10.00 scale
    attendance_percentage NUMERIC(5, 2)
);

-- Source 3: Learning Management System / LMS (Moodle / Canvas OLTP)
DROP TABLE IF EXISTS staging.src_lms_activity CASCADE;
CREATE TABLE staging.src_lms_activity (
    event_id VARCHAR(60),
    user_email VARCHAR(150),        -- Semantic link via email
    lms_course_code VARCHAR(50),
    action_type VARCHAR(50),        -- e.g., 'QUIZ_SUBMIT', 'ASSIGNMENT_UPLOAD', 'FORUM_POST', 'LECTURE_VIEW'
    event_timestamp VARCHAR(40),    -- ISO or epoch string
    time_spent_seconds INT,
    score_obtained NUMERIC(6, 2),
    max_score NUMERIC(6, 2)
);

-- Source 4: Fee & Finance Management System (Enterprise ERP)
DROP TABLE IF EXISTS staging.src_fee_finance CASCADE;
CREATE TABLE staging.src_fee_finance (
    txn_ref_id VARCHAR(60),
    student_ident_val VARCHAR(60),  -- Could be app_id or enrollment_no depending on semester!
    fee_type_code VARCHAR(50),      -- e.g., 'TUITION', 'HOSTEL', 'LAB', 'LIBRARY'
    term_period VARCHAR(50),
    billed_amount NUMERIC(12, 2),
    concession_amount NUMERIC(12, 2),
    amount_paid NUMERIC(12, 2),
    payment_mode VARCHAR(40),       -- 'UPI', 'NEFT', 'CASH', 'DEMAND_DRAFT'
    payment_date VARCHAR(30),
    clearance_status VARCHAR(30)    -- 'CLEARED', 'PENDING', 'BOUNCED'
);

-- Source 5: Koha Library Automation System
DROP TABLE IF EXISTS staging.src_library_koha CASCADE;
CREATE TABLE staging.src_library_koha (
    issue_id VARCHAR(60),
    patron_card_no VARCHAR(60),     -- Barcode or student roll no
    patron_email VARCHAR(150),
    book_isbn VARCHAR(40),
    book_title VARCHAR(200),
    subject_category VARCHAR(100),
    checkout_date VARCHAR(30),
    due_date VARCHAR(30),
    return_date VARCHAR(30),
    fine_assessed NUMERIC(8, 2),
    fine_collected NUMERIC(8, 2)
);


-- ============================================================================
-- 2. DIMENSIONAL LAYER: CONFORMED & SNOWFLAKE DIMENSIONS (edw_dim)
-- ============================================================================

-- Conformed Date Dimension (Essential Kimball Bus Architecture)
DROP TABLE IF EXISTS edw_dim.dim_date CASCADE;
CREATE TABLE edw_dim.dim_date (
    date_key INT PRIMARY KEY,               -- Format: YYYYMMDD
    full_date DATE NOT NULL,
    calendar_day INT NOT NULL,
    calendar_month INT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    calendar_quarter INT NOT NULL,
    quarter_name VARCHAR(10) NOT NULL,
    calendar_year INT NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    academic_year VARCHAR(20) NOT NULL      -- e.g., '2023-2024'
);

-- Conformed Academic Semester/Term Dimension
DROP TABLE IF EXISTS edw_dim.dim_semester CASCADE;
CREATE TABLE edw_dim.dim_semester (
    semester_key SERIAL PRIMARY KEY,
    semester_code VARCHAR(30) UNIQUE NOT NULL, -- e.g., 'SEM-2023-FALL'
    academic_term VARCHAR(20) NOT NULL,        -- 'Fall', 'Spring', 'Summer'
    academic_year VARCHAR(20) NOT NULL,        -- '2023-2024'
    start_date DATE,
    end_date DATE,
    is_current_term BOOLEAN DEFAULT FALSE
);

-- SNOWFLAKE HIERARCHY PART 1: College / Faculty School
DROP TABLE IF EXISTS edw_dim.dim_school_college CASCADE;
CREATE TABLE edw_dim.dim_school_college (
    college_key SERIAL PRIMARY KEY,
    college_code VARCHAR(30) UNIQUE NOT NULL, -- e.g., 'ENG_COLLEGE', 'MGMT_COLLEGE'
    college_name VARCHAR(150) NOT NULL,
    dean_name VARCHAR(100),
    building_location VARCHAR(100)
);

-- SNOWFLAKE HIERARCHY PART 2: Department (Points to College)
DROP TABLE IF EXISTS edw_dim.dim_department CASCADE;
CREATE TABLE edw_dim.dim_department (
    department_key SERIAL PRIMARY KEY,
    department_code VARCHAR(30) UNIQUE NOT NULL, -- e.g., 'CSE', 'ECE', 'MBA'
    department_name VARCHAR(100) NOT NULL,
    college_key INT REFERENCES edw_dim.dim_school_college(college_key),
    head_of_department VARCHAR(100)
);

-- SNOWFLAKE HIERARCHY PART 3: Degree Program (Points to Department)
DROP TABLE IF EXISTS edw_dim.dim_program CASCADE;
CREATE TABLE edw_dim.dim_program (
    program_key SERIAL PRIMARY KEY,
    program_code VARCHAR(50) UNIQUE NOT NULL,   -- e.g., 'BTECH_CSE', 'MTECH_AI'
    program_name VARCHAR(150) NOT NULL,
    degree_level VARCHAR(30) NOT NULL,          -- 'Undergraduate', 'Postgraduate', 'Doctoral'
    duration_years INT NOT NULL,
    department_key INT REFERENCES edw_dim.dim_department(department_key)
);

-- Conformed Student Dimension (SCD Type 2 for tracking major/academic status shifts)
DROP TABLE IF EXISTS edw_dim.dim_student CASCADE;
CREATE TABLE edw_dim.dim_student (
    student_key SERIAL PRIMARY KEY,             -- Surrogate Key
    student_natural_id VARCHAR(50) NOT NULL,    -- Unified Student Identifier (REG_NO or APP_NO)
    admissions_app_no VARCHAR(50),
    official_email VARCHAR(150),
    full_name VARCHAR(150) NOT NULL,
    phone_no VARCHAR(25),
    gender VARCHAR(20),
    admission_category VARCHAR(50),
    program_key INT REFERENCES edw_dim.dim_program(program_key),
    academic_status VARCHAR(40) NOT NULL,       -- 'ACTIVE', 'GRADUATED', 'PROBATION', 'WITHDRAWN'
    batch_year INT NOT NULL,
    -- SCD Type 2 Audit Metadata
    scd_start_date DATE NOT NULL,
    scd_end_date DATE NOT NULL,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX idx_dim_student_nat ON edw_dim.dim_student(student_natural_id);
CREATE INDEX idx_dim_student_email ON edw_dim.dim_student(official_email);

-- Conformed Instructor Dimension
DROP TABLE IF EXISTS edw_dim.dim_instructor CASCADE;
CREATE TABLE edw_dim.dim_instructor (
    instructor_key SERIAL PRIMARY KEY,
    emp_id VARCHAR(50) UNIQUE NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    designation VARCHAR(60),                    -- 'Professor', 'Associate Professor', 'Assistant Professor'
    department_key INT REFERENCES edw_dim.dim_department(department_key),
    qualification VARCHAR(100)
);

-- Conformed Course Dimension
DROP TABLE IF EXISTS edw_dim.dim_course CASCADE;
CREATE TABLE edw_dim.dim_course (
    course_key SERIAL PRIMARY KEY,
    course_code VARCHAR(50) UNIQUE NOT NULL,
    course_title VARCHAR(150) NOT NULL,
    credit_hours INT NOT NULL,
    department_key INT REFERENCES edw_dim.dim_department(department_key),
    course_level VARCHAR(30)                    -- 'Foundation', 'Core', 'Elective', 'Capstone'
);

-- Fee Category Dimension
DROP TABLE IF EXISTS edw_dim.dim_fee_category CASCADE;
CREATE TABLE edw_dim.dim_fee_category (
    fee_cat_key SERIAL PRIMARY KEY,
    fee_type_code VARCHAR(40) UNIQUE NOT NULL,  -- 'TUITION', 'HOSTEL', 'LAB', 'EXAM'
    fee_category_name VARCHAR(100) NOT NULL,
    is_refundable BOOLEAN DEFAULT FALSE
);

-- Library Asset Dimension
DROP TABLE IF EXISTS edw_dim.dim_library_asset CASCADE;
CREATE TABLE edw_dim.dim_library_asset (
    asset_key SERIAL PRIMARY KEY,
    isbn VARCHAR(40) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    subject_category VARCHAR(100),
    publisher VARCHAR(150),
    edition VARCHAR(30)
);


-- ============================================================================
-- 3. FACT TABLES: STAR SCHEMA DESIGN (edw_fact)
-- ============================================================================

-- Fact 1: Course Enrollment & Grades (Grain: One row per student per course per semester)
DROP TABLE IF EXISTS edw_fact.fact_course_enrollment_grades CASCADE;
CREATE TABLE edw_fact.fact_course_enrollment_grades (
    enrollment_grade_id SERIAL PRIMARY KEY,
    student_key INT NOT NULL REFERENCES edw_dim.dim_student(student_key),
    course_key INT NOT NULL REFERENCES edw_dim.dim_course(course_key),
    semester_key INT NOT NULL REFERENCES edw_dim.dim_semester(semester_key),
    instructor_key INT NOT NULL REFERENCES edw_dim.dim_instructor(instructor_key),
    date_key INT NOT NULL REFERENCES edw_dim.dim_date(date_key),
    -- Additive and Semi-additive Measures
    credits_attempted INT NOT NULL,
    credits_earned INT NOT NULL,
    grade_points NUMERIC(5, 2) NOT NULL,
    total_grade_points NUMERIC(6, 2) NOT NULL,  -- credits * grade_points
    attendance_percentage NUMERIC(5, 2) NOT NULL,
    is_passed BOOLEAN NOT NULL
);

-- Fact 2: LMS Activity & Engagement (Grain: One row per aggregated student-course daily interaction)
DROP TABLE IF EXISTS edw_fact.fact_lms_activity CASCADE;
CREATE TABLE edw_fact.fact_lms_activity (
    lms_activity_id SERIAL PRIMARY KEY,
    student_key INT NOT NULL REFERENCES edw_dim.dim_student(student_key),
    course_key INT NOT NULL REFERENCES edw_dim.dim_course(course_key),
    date_key INT NOT NULL REFERENCES edw_dim.dim_date(date_key),
    semester_key INT NOT NULL REFERENCES edw_dim.dim_semester(semester_key),
    -- Engagement Measures
    total_logins_count INT DEFAULT 0,
    total_time_spent_minutes NUMERIC(8, 2) DEFAULT 0,
    content_views_count INT DEFAULT 0,
    forum_posts_count INT DEFAULT 0,
    assignment_submissions_count INT DEFAULT 0,
    quiz_attempts_count INT DEFAULT 0,
    avg_quiz_score_pct NUMERIC(5, 2) DEFAULT 0
);

-- Fact 3: Fee Transactions & Billing (Grain: One row per fee transaction)
DROP TABLE IF EXISTS edw_fact.fact_fee_transactions CASCADE;
CREATE TABLE edw_fact.fact_fee_transactions (
    fee_txn_id SERIAL PRIMARY KEY,
    txn_ref_id VARCHAR(60) NOT NULL,
    student_key INT NOT NULL REFERENCES edw_dim.dim_student(student_key),
    fee_cat_key INT NOT NULL REFERENCES edw_dim.dim_fee_category(fee_cat_key),
    semester_key INT NOT NULL REFERENCES edw_dim.dim_semester(semester_key),
    date_key INT NOT NULL REFERENCES edw_dim.dim_date(date_key),
    -- Financial Measures
    billed_amount NUMERIC(12, 2) NOT NULL,
    concession_amount NUMERIC(12, 2) DEFAULT 0.00,
    net_payable_amount NUMERIC(12, 2) NOT NULL,
    paid_amount NUMERIC(12, 2) NOT NULL,
    outstanding_balance NUMERIC(12, 2) NOT NULL
);

-- Fact 4: Library Circulation (Grain: One row per book checkout/return transaction)
DROP TABLE IF EXISTS edw_fact.fact_library_circulation CASCADE;
CREATE TABLE edw_fact.fact_library_circulation (
    circulation_id SERIAL PRIMARY KEY,
    student_key INT NOT NULL REFERENCES edw_dim.dim_student(student_key),
    asset_key INT NOT NULL REFERENCES edw_dim.dim_library_asset(asset_key),
    checkout_date_key INT NOT NULL REFERENCES edw_dim.dim_date(date_key),
    return_date_key INT REFERENCES edw_dim.dim_date(date_key),
    -- Circulation Measures
    loan_duration_days INT,
    is_overdue BOOLEAN DEFAULT FALSE,
    fine_assessed NUMERIC(8, 2) DEFAULT 0.00,
    fine_collected NUMERIC(8, 2) DEFAULT 0.00
);

-- Fact 5: Student 360 Periodic Monthly Snapshot (Grain: One row per student per month)
DROP TABLE IF EXISTS edw_fact.fact_student_academic_360_monthly CASCADE;
CREATE TABLE edw_fact.fact_student_academic_360_monthly (
    snapshot_id SERIAL PRIMARY KEY,
    student_key INT NOT NULL REFERENCES edw_dim.dim_student(student_key),
    semester_key INT NOT NULL REFERENCES edw_dim.dim_semester(semester_key),
    snapshot_year_month INT NOT NULL,           -- Format: YYYYMM
    -- Consolidated Cross-Domain Metrics
    current_gpa NUMERIC(4, 2),
    avg_attendance_pct NUMERIC(5, 2),
    monthly_lms_minutes NUMERIC(8, 2),
    total_lms_activities INT,
    library_books_borrowed INT,
    fee_dues_outstanding NUMERIC(12, 2),
    -- At-Risk Indicator Flag
    is_academically_at_risk BOOLEAN DEFAULT FALSE,
    is_financially_at_risk BOOLEAN DEFAULT FALSE
);
