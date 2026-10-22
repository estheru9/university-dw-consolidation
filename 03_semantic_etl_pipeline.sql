-- ============================================================================
-- SCRIPT 03: SEMANTIC ETL & DIMENSIONAL LOADING PIPELINE
-- Project: Semantic Data Integration Across Multi-source Warehouses
-- Domain: University Data Warehouse Consolidation
-- ============================================================================

-- ============================================================================
-- 1. SEMANTIC ENTITY RESOLUTION & CONFORMED DIMENSIONS POPULATION
-- ============================================================================

-- A. Populate Conformed Instructors (Extract & Deduplicate from SIS)
INSERT INTO edw_dim.dim_instructor (emp_id, full_name, designation, department_key, qualification)
SELECT DISTINCT 
    sis.instructor_emp_id AS emp_id,
    sis.instructor_name AS full_name,
    'Assistant Professor' AS designation,
    dept.department_key,
    'Ph.D. / Master of Technology' AS qualification
FROM staging.src_sis_academics sis
JOIN edw_dim.dim_department dept ON sis.department_name = dept.department_code
WHERE NOT EXISTS (
    SELECT 1 FROM edw_dim.dim_instructor i WHERE i.emp_id = sis.instructor_emp_id
);

-- B. Populate Conformed Courses (Normalize from SIS Offerings)
INSERT INTO edw_dim.dim_course (course_code, course_title, credit_hours, department_key, course_level)
SELECT DISTINCT
    sis.course_code,
    sis.course_title,
    sis.credits,
    dept.department_key,
    CASE 
        WHEN sis.course_code LIKE '%101%' THEN 'Foundation'
        WHEN sis.course_code LIKE '%201%' THEN 'Core'
        ELSE 'Advanced'
    END AS course_level
FROM staging.src_sis_academics sis
JOIN edw_dim.dim_department dept ON sis.department_name = dept.department_code
WHERE NOT EXISTS (
    SELECT 1 FROM edw_dim.dim_course c WHERE c.course_code = sis.course_code
);

-- C. Semantic Entity Resolution for Students
-- Reconciles Admissions (pre-enrollment) and SIS (enrolled), resolving alternate email/keys
INSERT INTO edw_dim.dim_student (
    student_natural_id,
    admissions_app_no,
    official_email,
    full_name,
    phone_no,
    gender,
    admission_category,
    program_key,
    academic_status,
    batch_year,
    scd_start_date,
    scd_end_date,
    is_current
)
SELECT 
    COALESCE(sis.enrollment_no, adm.app_id) AS student_natural_id,
    adm.app_id AS admissions_app_no,
    COALESCE(sis.official_email, adm.applicant_email) AS official_email,
    COALESCE(sis.full_name, adm.candidate_name) AS full_name,
    adm.phone_no,
    'Not Specified' AS gender,
    adm.admission_category,
    prog.program_key,
    CASE 
        WHEN adm.admission_status = 'WITHDRAWN' THEN 'WITHDRAWN'
        ELSE 'ACTIVE'
    END AS academic_status,
    2023 AS batch_year,
    '2023-08-01'::DATE AS scd_start_date,
    '9999-12-31'::DATE AS scd_end_date,
    TRUE AS is_current
FROM staging.src_admissions adm
FULL OUTER JOIN (
    SELECT DISTINCT 
        enrollment_no, 
        admissions_ref_no, 
        full_name, 
        official_email, 
        program_id 
    FROM staging.src_sis_academics
) sis ON adm.app_id = sis.admissions_ref_no
LEFT JOIN edw_dim.dim_program prog ON sis.program_id = prog.program_code
WHERE NOT EXISTS (
    SELECT 1 FROM edw_dim.dim_student s 
    WHERE s.student_natural_id = COALESCE(sis.enrollment_no, adm.app_id)
);


-- ============================================================================
-- 2. POPULATE STAR SCHEMA FACT TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Fact 1: Course Enrollment & Grades
-- ----------------------------------------------------------------------------
INSERT INTO edw_fact.fact_course_enrollment_grades (
    student_key,
    course_key,
    semester_key,
    instructor_key,
    date_key,
    credits_attempted,
    credits_earned,
    grade_points,
    total_grade_points,
    attendance_percentage,
    is_passed
)
SELECT 
    stu.student_key,
    crs.course_key,
    sem.semester_key,
    inst.instructor_key,
    20231215 AS date_key, -- End of term grading date
    sis.credits AS credits_attempted,
    CASE WHEN sis.grade_letter <> 'F' THEN sis.credits ELSE 0 END AS credits_earned,
    sis.grade_points,
    (sis.credits * sis.grade_points) AS total_grade_points,
    sis.attendance_percentage,
    CASE WHEN sis.grade_letter <> 'F' THEN TRUE ELSE FALSE END AS is_passed
FROM staging.src_sis_academics sis
JOIN edw_dim.dim_student stu ON sis.enrollment_no = stu.student_natural_id AND stu.is_current = TRUE
JOIN edw_dim.dim_course crs ON sis.course_code = crs.course_code
JOIN edw_dim.dim_instructor inst ON sis.instructor_emp_id = inst.emp_id
JOIN edw_dim.dim_semester sem ON sem.semester_code = 'SEM-2023-FALL';

-- ----------------------------------------------------------------------------
-- Fact 2: LMS Activity & Engagement (Aggregated to Daily Student-Course Grain)
-- ----------------------------------------------------------------------------
INSERT INTO edw_fact.fact_lms_activity (
    student_key,
    course_key,
    date_key,
    semester_key,
    total_logins_count,
    total_time_spent_minutes,
    content_views_count,
    forum_posts_count,
    assignment_submissions_count,
    quiz_attempts_count,
    avg_quiz_score_pct
)
SELECT 
    stu.student_key,
    crs.course_key,
    CAST(TO_CHAR(CAST(lms.event_timestamp AS TIMESTAMP), 'YYYYMMDD') AS INT) AS date_key,
    sem.semester_key,
    COUNT(DISTINCT lms.event_id) AS total_logins_count,
    ROUND(SUM(COALESCE(lms.time_spent_seconds, 0)) / 60.0, 2) AS total_time_spent_minutes,
    SUM(CASE WHEN lms.action_type = 'LECTURE_VIEW' THEN 1 ELSE 0 END) AS content_views_count,
    SUM(CASE WHEN lms.action_type = 'FORUM_POST' THEN 1 ELSE 0 END) AS forum_posts_count,
    SUM(CASE WHEN lms.action_type = 'ASSIGNMENT_UPLOAD' THEN 1 ELSE 0 END) AS assignment_submissions_count,
    SUM(CASE WHEN lms.action_type = 'QUIZ_SUBMIT' THEN 1 ELSE 0 END) AS quiz_attempts_count,
    ROUND(AVG(CASE WHEN lms.max_score > 0 THEN (lms.score_obtained / lms.max_score) * 100 ELSE NULL END), 2) AS avg_quiz_score_pct
FROM staging.src_lms_activity lms
JOIN edw_dim.dim_student stu ON LOWER(lms.user_email) = LOWER(stu.official_email) AND stu.is_current = TRUE
JOIN edw_dim.dim_course crs ON lms.lms_course_code = crs.course_code
JOIN edw_dim.dim_semester sem ON sem.semester_code = 'SEM-2023-FALL'
GROUP BY 
    stu.student_key,
    crs.course_key,
    CAST(TO_CHAR(CAST(lms.event_timestamp AS TIMESTAMP), 'YYYYMMDD') AS INT),
    sem.semester_key;

-- ----------------------------------------------------------------------------
-- Fact 3: Fee Transactions & Financial Audits
-- Reconciles heterogeneous keys (either APP_NO or REG_NO)
-- ----------------------------------------------------------------------------
INSERT INTO edw_fact.fact_fee_transactions (
    txn_ref_id,
    student_key,
    fee_cat_key,
    semester_key,
    date_key,
    billed_amount,
    concession_amount,
    net_payable_amount,
    paid_amount,
    outstanding_balance
)
SELECT 
    fee.txn_ref_id,
    stu.student_key,
    cat.fee_cat_key,
    sem.semester_key,
    CAST(REPLACE(fee.payment_date, '-', '') AS INT) AS date_key,
    fee.billed_amount,
    fee.concession_amount,
    (fee.billed_amount - fee.concession_amount) AS net_payable_amount,
    fee.amount_paid,
    ((fee.billed_amount - fee.concession_amount) - fee.amount_paid) AS outstanding_balance
FROM staging.src_fee_finance fee
JOIN edw_dim.dim_student stu ON (
    fee.student_ident_val = stu.student_natural_id 
    OR fee.student_ident_val = stu.admissions_app_no
) AND stu.is_current = TRUE
JOIN edw_dim.dim_fee_category cat ON fee.fee_type_code = cat.fee_type_code
JOIN edw_dim.dim_semester sem ON fee.term_period = sem.semester_code;

-- ----------------------------------------------------------------------------
-- Fact 4: Library Circulation
-- Reconciles patron by either student enrollment roll or email
-- ----------------------------------------------------------------------------
INSERT INTO edw_fact.fact_library_circulation (
    student_key,
    asset_key,
    checkout_date_key,
    return_date_key,
    loan_duration_days,
    is_overdue,
    fine_assessed,
    fine_collected
)
SELECT 
    stu.student_key,
    lib.asset_key,
    CAST(REPLACE(koha.checkout_date, '-', '') AS INT) AS checkout_date_key,
    CAST(REPLACE(koha.return_date, '-', '') AS INT) AS return_date_key,
    (CAST(koha.return_date AS DATE) - CAST(koha.checkout_date AS DATE)) AS loan_duration_days,
    CASE WHEN CAST(koha.return_date AS DATE) > CAST(koha.due_date AS DATE) THEN TRUE ELSE FALSE END AS is_overdue,
    koha.fine_assessed,
    koha.fine_collected
FROM staging.src_library_koha koha
JOIN edw_dim.dim_student stu ON (
    koha.patron_card_no = stu.student_natural_id 
    OR LOWER(koha.patron_email) = LOWER(stu.official_email)
) AND stu.is_current = TRUE
JOIN edw_dim.dim_library_asset lib ON koha.book_isbn = lib.isbn;

-- ----------------------------------------------------------------------------
-- Fact 5: Student 360 Consolidated Periodic Monthly Snapshot
-- Synthesizes Cross-Domain metrics to generate Early Warning Flags
-- ----------------------------------------------------------------------------
INSERT INTO edw_fact.fact_student_academic_360_monthly (
    student_key,
    semester_key,
    snapshot_year_month,
    current_gpa,
    avg_attendance_pct,
    monthly_lms_minutes,
    total_lms_activities,
    library_books_borrowed,
    fee_dues_outstanding,
    is_academically_at_risk,
    is_financially_at_risk
)
SELECT 
    stu.student_key,
    1 AS semester_key,
    202312 AS snapshot_year_month,
    COALESCE(ROUND(SUM(grd.total_grade_points) / NULLIF(SUM(grd.credits_attempted), 0), 2), 0.00) AS current_gpa,
    COALESCE(ROUND(AVG(grd.attendance_percentage), 2), 0.00) AS avg_attendance_pct,
    COALESCE(ROUND(SUM(lms.total_time_spent_minutes), 2), 0.00) AS monthly_lms_minutes,
    COALESCE(SUM(lms.total_logins_count), 0) AS total_lms_activities,
    COALESCE(COUNT(DISTINCT circ.circulation_id), 0) AS library_books_borrowed,
    COALESCE(MAX(fee.total_dues), 0.00) AS fee_dues_outstanding,
    -- Early Warning Academic Risk Flag: GPA < 6.0 OR Attendance < 75%
    CASE 
        WHEN (COALESCE(SUM(grd.total_grade_points) / NULLIF(SUM(grd.credits_attempted), 0), 0) < 6.00)
             OR (COALESCE(AVG(grd.attendance_percentage), 100) < 75.00) 
        THEN TRUE 
        ELSE FALSE 
    END AS is_academically_at_risk,
    -- Early Warning Financial Risk Flag: Outstanding balance > 0
    CASE 
        WHEN COALESCE(MAX(fee.total_dues), 0.00) > 0.00 THEN TRUE 
        ELSE FALSE 
    END AS is_financially_at_risk
FROM edw_dim.dim_student stu
LEFT JOIN edw_fact.fact_course_enrollment_grades grd ON stu.student_key = grd.student_key
LEFT JOIN edw_fact.fact_lms_activity lms ON stu.student_key = lms.student_key
LEFT JOIN edw_fact.fact_library_circulation circ ON stu.student_key = circ.student_key
LEFT JOIN (
    SELECT student_key, SUM(outstanding_balance) AS total_dues
    FROM edw_fact.fact_fee_transactions
    GROUP BY student_key
) fee ON stu.student_key = fee.student_key
WHERE stu.is_current = TRUE AND stu.academic_status = 'ACTIVE'
GROUP BY stu.student_key;
