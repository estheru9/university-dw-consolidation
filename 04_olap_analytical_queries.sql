-- ============================================================================
-- SCRIPT 04: OLAP ANALYTICAL QUERIES & MULTI-DIMENSIONAL MARTS
-- Project: Semantic Data Integration Across Multi-source Warehouses
-- Domain: University Data Warehouse Consolidation
-- ============================================================================

-- ============================================================================
-- 1. ROLL-UP QUERY: ACADEMIC PERFORMANCE ACROSS SNOWFLAKE HIERARCHY
-- Rolls up from Course -> Program -> Department -> College
-- ============================================================================
SELECT 
    col.college_name,
    dept.department_name,
    prog.program_name,
    COUNT(DISTINCT fce.student_key) AS total_enrolled_students,
    SUM(fce.credits_attempted) AS total_credits_attempted,
    SUM(fce.credits_earned) AS total_credits_cleared,
    ROUND(SUM(fce.total_grade_points) / NULLIF(SUM(fce.credits_attempted), 0), 2) AS weighted_avg_gpa,
    ROUND(AVG(fce.attendance_percentage), 2) AS avg_attendance_pct,
    ROUND((SUM(CASE WHEN fce.is_passed THEN 1 ELSE 0 END)::NUMERIC / COUNT(*)) * 100, 2) AS overall_pass_rate_pct
FROM edw_fact.fact_course_enrollment_grades fce
JOIN edw_dim.dim_student stu ON fce.student_key = stu.student_key
JOIN edw_dim.dim_program prog ON stu.program_key = prog.program_key
JOIN edw_dim.dim_department dept ON prog.department_key = dept.department_key
JOIN edw_dim.dim_school_college col ON dept.college_key = col.college_key
GROUP BY ROLLUP (col.college_name, dept.department_name, prog.program_name);


-- ============================================================================
-- 2. DRILL-DOWN & SLICE-AND-DICE: REVENUE & DUES BY ADMISSION CATEGORY
-- Slices by Semester ('SEM-2023-FALL') and dices by Admission Category & Department
-- ============================================================================
SELECT 
    dept.department_code,
    stu.admission_category,
    cat.fee_category_name,
    COUNT(DISTINCT fee.student_key) AS student_headcount,
    SUM(fee.billed_amount) AS total_billed,
    SUM(fee.concession_amount) AS total_concessions,
    SUM(fee.paid_amount) AS total_collected,
    SUM(fee.outstanding_balance) AS total_unpaid_dues,
    ROUND((SUM(fee.paid_amount) / NULLIF(SUM(fee.net_payable_amount), 0)) * 100, 2) AS collection_efficiency_pct
FROM edw_fact.fact_fee_transactions fee
JOIN edw_dim.dim_student stu ON fee.student_key = stu.student_key
JOIN edw_dim.dim_program prog ON stu.program_key = prog.program_key
JOIN edw_dim.dim_department dept ON prog.department_key = dept.department_key
JOIN edw_dim.dim_fee_category cat ON fee.fee_cat_key = cat.fee_cat_key
JOIN edw_dim.dim_semester sem ON fee.semester_key = sem.semester_key
WHERE sem.semester_code = 'SEM-2023-FALL'
GROUP BY dept.department_code, stu.admission_category, cat.fee_category_name
ORDER BY total_unpaid_dues DESC;


-- ============================================================================
-- 3. CROSS-DOMAIN SEMANTIC CORRELATION: DIGITAL ENGAGEMENT VS. ACADEMIC OUTCOME
-- Demonstrates the core value of consolidating LMS, Library, and SIS
-- ============================================================================
WITH student_academics AS (
    SELECT 
        student_key,
        ROUND(SUM(total_grade_points) / NULLIF(SUM(credits_attempted), 0), 2) AS gpa,
        ROUND(AVG(attendance_percentage), 2) AS class_attendance
    FROM edw_fact.fact_course_enrollment_grades
    GROUP BY student_key
),
student_lms AS (
    SELECT 
        student_key,
        SUM(total_time_spent_minutes) AS total_lms_time_mins,
        SUM(quiz_attempts_count + assignment_submissions_count) AS total_assignments_quizzes,
        ROUND(AVG(avg_quiz_score_pct), 2) AS avg_lms_quiz_score
    FROM edw_fact.fact_lms_activity
    GROUP BY student_key
),
student_library AS (
    SELECT 
        student_key,
        COUNT(circulation_id) AS total_books_issued
    FROM edw_fact.fact_library_circulation
    GROUP BY student_key
)
SELECT 
    stu.student_natural_id,
    stu.full_name,
    dept.department_code,
    acad.gpa,
    acad.class_attendance,
    COALESCE(lms.total_lms_time_mins, 0) AS lms_engagement_mins,
    COALESCE(lms.total_assignments_quizzes, 0) AS lms_submissions,
    COALESCE(lms.avg_lms_quiz_score, 0) AS lms_quiz_avg,
    COALESCE(lib.total_books_issued, 0) AS library_books_borrowed
FROM edw_dim.dim_student stu
JOIN edw_dim.dim_program prog ON stu.program_key = prog.program_key
JOIN edw_dim.dim_department dept ON prog.department_key = dept.department_key
JOIN student_academics acad ON stu.student_key = acad.student_key
LEFT JOIN student_lms lms ON stu.student_key = lms.student_key
LEFT JOIN student_library lib ON stu.student_key = lib.student_key
ORDER BY acad.gpa DESC;


-- ============================================================================
-- 4. STUDENT 360 EARLY WARNING & INTERVENTION MART
-- Filters students flagged as academically or financially at risk for intervention
-- ============================================================================
SELECT 
    snap.snapshot_year_month,
    stu.student_natural_id AS student_id,
    stu.full_name,
    stu.official_email,
    stu.phone_no,
    dept.department_name,
    snap.current_gpa,
    snap.avg_attendance_pct,
    snap.monthly_lms_minutes,
    snap.fee_dues_outstanding,
    snap.is_academically_at_risk,
    snap.is_financially_at_risk,
    CASE 
        WHEN snap.is_academically_at_risk AND snap.is_financially_at_risk 
            THEN 'CRITICAL: Dual Academic & Financial Probation'
        WHEN snap.is_academically_at_risk 
            THEN 'WARNING: Academic Mentorship Required'
        WHEN snap.is_financially_at_risk 
            THEN 'ACTION: Financial Aid / Fee Recovery Follow-up'
        ELSE 'GOOD STANDING'
    END AS intervention_priority
FROM edw_fact.fact_student_academic_360_monthly snap
JOIN edw_dim.dim_student stu ON snap.student_key = stu.student_key
JOIN edw_dim.dim_program prog ON stu.program_key = prog.program_key
JOIN edw_dim.dim_department dept ON prog.department_key = dept.department_key
WHERE snap.is_academically_at_risk = TRUE OR snap.is_financially_at_risk = TRUE;


-- ============================================================================
-- 5. COURSE & INSTRUCTOR EFFECTIVENESS AUDIT
-- Evaluates grading distribution, class size, and pass rates by faculty
-- ============================================================================
SELECT 
    inst.emp_id,
    inst.full_name AS instructor_name,
    crs.course_code,
    crs.course_title,
    COUNT(fce.enrollment_grade_id) AS total_students_graded,
    ROUND(AVG(fce.grade_points), 2) AS avg_class_grade_point,
    ROUND(AVG(fce.attendance_percentage), 2) AS avg_class_attendance,
    SUM(CASE WHEN fce.is_passed THEN 1 ELSE 0 END) AS students_passed,
    SUM(CASE WHEN NOT fce.is_passed THEN 1 ELSE 0 END) AS students_failed,
    ROUND((SUM(CASE WHEN fce.is_passed THEN 1 ELSE 0 END)::NUMERIC / COUNT(fce.enrollment_grade_id)) * 100, 2) AS pass_percentage
FROM edw_fact.fact_course_enrollment_grades fce
JOIN edw_dim.dim_instructor inst ON fce.instructor_key = inst.instructor_key
JOIN edw_dim.dim_course crs ON fce.course_key = crs.course_key
GROUP BY inst.emp_id, inst.full_name, crs.course_code, crs.course_title
ORDER BY avg_class_grade_point DESC;
