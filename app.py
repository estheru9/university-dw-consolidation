import streamlit as st
import pandas as pd
import sqlite3
import plotly.express as px
import plotly.graph_objects as go
import os

# Set Streamlit Page Configuration
st.set_page_config(
    page_title="University Data Warehouse Consolidation | EDW",
    page_icon="🎓",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom Styling
st.markdown("""
<style>
    .main-title {
        font-size: 2.2rem;
        font-weight: 800;
        color: #1E3A8A;
        margin-bottom: 0px;
    }
    .sub-title {
        font-size: 1.05rem;
        color: #4B5563;
        margin-bottom: 15px;
    }
    .mentor-badge {
        display: inline-block;
        background-color: #EEF2FF;
        color: #3730A3;
        padding: 4px 12px;
        border-radius: 9999px;
        font-weight: 600;
        font-size: 0.85rem;
        margin-bottom: 20px;
    }
    .metric-card {
        background: #F8FAFC;
        border-radius: 8px;
        padding: 15px;
        border: 1px solid #E2E8F0;
    }
</style>
""", unsafe_allow_html=True)

# Database Initialization Function
@st.cache_resource
def get_database_connection():
    conn = sqlite3.connect(":memory:", check_same_thread=False)
    cursor = conn.cursor()

    # DDL Execution for Staging and Dimensions
    cursor.executescript("""
    -- 1. STAGING TABLES
    CREATE TABLE src_admissions (
        app_id TEXT PRIMARY KEY,
        candidate_name TEXT,
        applicant_email TEXT,
        phone_no TEXT,
        allocated_branch_code TEXT,
        entrance_exam_rank INT,
        admission_category TEXT,
        admission_status TEXT,
        allotment_date TEXT,
        application_fee_paid REAL
    );

    CREATE TABLE src_sis_academics (
        enrollment_no TEXT,
        admissions_ref_no TEXT,
        full_name TEXT,
        official_email TEXT,
        program_id TEXT,
        department_name TEXT,
        academic_term TEXT,
        course_code TEXT,
        course_title TEXT,
        instructor_emp_id TEXT,
        instructor_name TEXT,
        credits INT,
        grade_letter TEXT,
        grade_points REAL,
        attendance_percentage REAL
    );

    CREATE TABLE src_lms_activity (
        event_id TEXT PRIMARY KEY,
        user_email TEXT,
        lms_course_code TEXT,
        action_type TEXT,
        event_timestamp TEXT,
        time_spent_seconds INT,
        score_obtained REAL,
        max_score REAL
    );

    CREATE TABLE src_fee_finance (
        txn_ref_id TEXT PRIMARY KEY,
        student_ident_val TEXT,
        fee_type_code TEXT,
        term_period TEXT,
        billed_amount REAL,
        concession_amount REAL,
        amount_paid REAL,
        payment_mode TEXT,
        payment_date TEXT,
        clearance_status TEXT
    );

    CREATE TABLE src_library_koha (
        issue_id TEXT PRIMARY KEY,
        patron_card_no TEXT,
        patron_email TEXT,
        book_isbn TEXT,
        book_title TEXT,
        subject_category TEXT,
        checkout_date TEXT,
        due_date TEXT,
        return_date TEXT,
        fine_assessed REAL,
        fine_collected REAL
    );

    -- 2. DIMENSIONS (SNOWFLAKE & CONFORMED)
    CREATE TABLE dim_school_college (
        college_key INTEGER PRIMARY KEY AUTOINCREMENT,
        college_code TEXT UNIQUE,
        college_name TEXT,
        dean_name TEXT,
        building_location TEXT
    );

    CREATE TABLE dim_department (
        department_key INTEGER PRIMARY KEY AUTOINCREMENT,
        department_code TEXT UNIQUE,
        department_name TEXT,
        college_key INT,
        head_of_department TEXT,
        FOREIGN KEY(college_key) REFERENCES dim_school_college(college_key)
    );

    CREATE TABLE dim_program (
        program_key INTEGER PRIMARY KEY AUTOINCREMENT,
        program_code TEXT UNIQUE,
        program_name TEXT,
        degree_level TEXT,
        duration_years INT,
        department_key INT,
        FOREIGN KEY(department_key) REFERENCES dim_department(department_key)
    );

    CREATE TABLE dim_student (
        student_key INTEGER PRIMARY KEY AUTOINCREMENT,
        student_natural_id TEXT,
        admissions_app_no TEXT,
        official_email TEXT,
        full_name TEXT,
        admission_category TEXT,
        program_key INT,
        academic_status TEXT,
        scd_start_date TEXT,
        scd_end_date TEXT,
        is_current INTEGER,
        FOREIGN KEY(program_key) REFERENCES dim_program(program_key)
    );

    CREATE TABLE dim_instructor (
        instructor_key INTEGER PRIMARY KEY AUTOINCREMENT,
        emp_id TEXT UNIQUE,
        full_name TEXT,
        designation TEXT,
        department_key INT,
        FOREIGN KEY(department_key) REFERENCES dim_department(department_key)
    );

    CREATE TABLE dim_course (
        course_key INTEGER PRIMARY KEY AUTOINCREMENT,
        course_code TEXT UNIQUE,
        course_title TEXT,
        credit_hours INT,
        department_key INT,
        course_level TEXT,
        FOREIGN KEY(department_key) REFERENCES dim_department(department_key)
    );

    CREATE TABLE dim_fee_category (
        fee_cat_key INTEGER PRIMARY KEY AUTOINCREMENT,
        fee_type_code TEXT UNIQUE,
        fee_category_name TEXT
    );

    CREATE TABLE dim_library_asset (
        asset_key INTEGER PRIMARY KEY AUTOINCREMENT,
        isbn TEXT UNIQUE,
        title TEXT,
        subject_category TEXT
    );

    CREATE TABLE dim_semester (
        semester_key INTEGER PRIMARY KEY AUTOINCREMENT,
        semester_code TEXT UNIQUE,
        academic_term TEXT,
        academic_year TEXT
    );

    -- 3. STAR SCHEMA FACT TABLES
    CREATE TABLE fact_course_enrollment_grades (
        enrollment_grade_id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_key INT,
        course_key INT,
        semester_key INT,
        instructor_key INT,
        credits_attempted INT,
        credits_earned INT,
        grade_points REAL,
        total_grade_points REAL,
        attendance_percentage REAL,
        is_passed INTEGER
    );

    CREATE TABLE fact_lms_activity (
        lms_activity_id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_key INT,
        course_key INT,
        semester_key INT,
        total_logins_count INT,
        total_time_spent_minutes REAL,
        assignments_submissions_count INT,
        quiz_attempts_count INT,
        avg_quiz_score_pct REAL
    );

    CREATE TABLE fact_fee_transactions (
        fee_txn_id INTEGER PRIMARY KEY AUTOINCREMENT,
        txn_ref_id TEXT,
        student_key INT,
        fee_cat_key INT,
        semester_key INT,
        billed_amount REAL,
        concession_amount REAL,
        paid_amount REAL,
        outstanding_balance REAL
    );

    CREATE TABLE fact_library_circulation (
        circulation_id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_key INT,
        asset_key INT,
        loan_duration_days INT,
        is_overdue INTEGER,
        fine_assessed REAL
    );

    CREATE TABLE fact_student_academic_360_monthly (
        snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_key INT,
        current_gpa REAL,
        avg_attendance_pct REAL,
        monthly_lms_minutes REAL,
        fee_dues_outstanding REAL,
        is_academically_at_risk INTEGER,
        is_financially_at_risk INTEGER
    );
    """)

    # Seed Sample Raw Staging Data
    cursor.executescript("""
    -- Seed Colleges & Departments
    INSERT INTO dim_school_college (college_code, college_name, dean_name, building_location) VALUES
    ('ENG_COLLEGE', 'School of Engineering & Technology', 'Dr. Ramesh Rao', 'Tech Block A'),
    ('MGMT_COLLEGE', 'School of Business & Management', 'Dr. Sunita Kapoor', 'Management Tower B');

    INSERT INTO dim_department (department_code, department_name, college_key, head_of_department) VALUES
    ('CSE', 'Computer Science & Engineering', 1, 'Dr. Anand Kumar'),
    ('ECE', 'Electronics & Communication', 1, 'Dr. Meena Iyer'),
    ('MBA', 'Management Studies', 2, 'Dr. Vikram Malhotra');

    INSERT INTO dim_program (program_code, program_name, degree_level, duration_years, department_key) VALUES
    ('BTECH_CSE', 'B.Tech in Computer Science', 'UG', 4, 1),
    ('BTECH_ECE', 'B.Tech in Electronics', 'UG', 4, 2),
    ('MBA_GEN', 'Master of Business Administration', 'PG', 2, 3);

    INSERT INTO dim_semester (semester_code, academic_term, academic_year) VALUES
    ('SEM-2023-FALL', 'Fall', '2023-2024'),
    ('SEM-2024-SPRING', 'Spring', '2023-2024');

    INSERT INTO dim_fee_category (fee_type_code, fee_category_name) VALUES
    ('TUITION', 'Academic Tuition Fee'),
    ('HOSTEL', 'Hostel Accommodation');

    INSERT INTO dim_library_asset (isbn, title, subject_category) VALUES
    ('978-0132350884', 'Clean Code', 'Computer Science'),
    ('978-0262033848', 'Introduction to Algorithms', 'Computer Science'),
    ('978-0134494166', 'Database System Concepts', 'Data Management'),
    ('978-0133856941', 'Marketing Management', 'Business Management');

    -- Insert Staging Raw Data
    INSERT INTO src_admissions VALUES
    ('APP-2023-0101', 'Aarav Sharma', 'aarav.sharma@gmail.com', '9876543210', 'CSE', 1240, 'Merit', 'CONFIRMED', '2023-06-15', 1500.00),
    ('APP-2023-0102', 'Priya Patel', 'priya.patel99@yahoo.com', '9876543211', 'CSE', 2410, 'Merit', 'CONFIRMED', '2023-06-16', 1500.00),
    ('APP-2023-0201', 'Rohan Verma', 'rohan.v@gmail.com', '9876543212', 'ECE', 3900, 'Management', 'CONFIRMED', '2023-06-20', 2500.00),
    ('APP-2023-0301', 'Sneha Reddy', 'sneha.reddy@outlook.com', '9876543213', 'MBA', 850, 'Merit', 'CONFIRMED', '2023-06-25', 2000.00);

    INSERT INTO src_sis_academics VALUES
    ('REG-2023-CS-0101', 'APP-2023-0101', 'Aarav Sharma', 'aarav.s@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS301', 'Database Engineering & DW', 'EMP-CS-01', 'Dr. Anand Kumar', 4, 'A+', 10.00, 94.50),
    ('REG-2023-CS-0101', 'APP-2023-0101', 'Aarav Sharma', 'aarav.s@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS302', 'Data Structures & Algorithms', 'EMP-CS-02', 'Prof. Neha Gupta', 4, 'A', 9.00, 91.00),
    ('REG-2023-CS-0102', 'APP-2023-0102', 'Priya Patel', 'priya.p@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS301', 'Database Engineering & DW', 'EMP-CS-01', 'Dr. Anand Kumar', 4, 'C', 5.00, 62.00),
    ('REG-2023-CS-0102', 'APP-2023-0102', 'Priya Patel', 'priya.p@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS302', 'Data Structures & Algorithms', 'EMP-CS-02', 'Prof. Neha Gupta', 4, 'F', 0.00, 58.50),
    ('REG-2023-EC-0201', 'APP-2023-0201', 'Rohan Verma', 'rohan.v@univ.edu', 'BTECH_ECE', 'ECE', '2023-Fall', 'EC201', 'Signals & Linear Systems', 'EMP-EC-01', 'Dr. Meena Iyer', 4, 'B', 7.00, 84.00),
    ('REG-2023-MB-0301', 'APP-2023-0301', 'Sneha Reddy', 'sneha.r@univ.edu', 'MBA_GEN', 'MBA', '2023-Fall', 'MB101', 'Strategic Marketing', 'EMP-MB-01', 'Dr. Vikram Malhotra', 3, 'A+', 10.00, 96.00);

    INSERT INTO src_lms_activity VALUES
    ('LMS-EVT-001', 'aarav.s@univ.edu', 'CS301', 'LECTURE_VIEW', '2023-09-15 10:15:00', 3600, NULL, NULL),
    ('LMS-EVT-002', 'aarav.s@univ.edu', 'CS301', 'QUIZ_SUBMIT', '2023-09-15 14:30:00', 1800, 19.5, 20.0),
    ('LMS-EVT-003', 'aarav.s@univ.edu', 'CS301', 'ASSIGNMENT_UPLOAD', '2023-10-20 23:10:00', 1200, 48.0, 50.0),
    ('LMS-EVT-005', 'priya.p@univ.edu', 'CS301', 'LECTURE_VIEW', '2023-09-15 11:00:00', 450, NULL, NULL),
    ('LMS-EVT-006', 'priya.p@univ.edu', 'CS301', 'QUIZ_SUBMIT', '2023-09-15 15:00:00', 600, 8.0, 20.0),
    ('LMS-EVT-007', 'rohan.v@univ.edu', 'EC201', 'ASSIGNMENT_UPLOAD', '2023-10-20 20:00:00', 2100, 38.0, 50.0),
    ('LMS-EVT-008', 'sneha.r@univ.edu', 'MB101', 'QUIZ_SUBMIT', '2023-11-12 18:00:00', 2400, 19.0, 20.0);

    INSERT INTO src_fee_finance VALUES
    ('TXN-2023-F01', 'APP-2023-0101', 'TUITION', 'SEM-2023-FALL', 85000.00, 10000.00, 75000.00, 'NEFT', '2023-08-10', 'CLEARED'),
    ('TXN-2023-F02', 'APP-2023-0102', 'TUITION', 'SEM-2023-FALL', 85000.00, 0.00, 40000.00, 'UPI', '2023-08-10', 'PARTIAL'),
    ('TXN-2023-F03', 'APP-2023-0201', 'TUITION', 'SEM-2023-FALL', 85000.00, 0.00, 85000.00, 'DEMAND_DRAFT', '2023-08-10', 'CLEARED'),
    ('TXN-2023-F04', 'APP-2023-0301', 'TUITION', 'SEM-2023-FALL', 120000.00, 20000.00, 100000.00, 'NEFT', '2023-08-10', 'CLEARED');

    INSERT INTO src_library_koha VALUES
    ('LIB-ISS-1001', 'REG-2023-CS-0101', 'aarav.s@univ.edu', '978-0132350884', 'Clean Code', 'Computer Science', '2023-09-15', '2023-09-30', '2023-09-28', 0.0, 0.0),
    ('LIB-ISS-1002', 'REG-2023-CS-0101', 'aarav.s@univ.edu', '978-0262033848', 'Introduction to Algorithms', 'Computer Science', '2023-10-20', '2023-11-05', '2023-11-04', 0.0, 0.0),
    ('LIB-ISS-1003', 'REG-2023-CS-0102', 'priya.p@univ.edu', '978-0134494166', 'Database System Concepts', 'Data Management', '2023-10-20', '2023-11-05', '2023-12-15', 40.0, 0.0),
    ('LIB-ISS-1004', 'REG-2023-MB-0301', 'sneha.r@univ.edu', '978-0133856941', 'Marketing Management', 'Business Administration', '2023-11-12', '2023-11-27', '2023-11-25', 0.0, 0.0);
    """)

    # Run Semantic Integration and Fact Population
    cursor.executescript("""
    -- Populate dim_instructor
    INSERT INTO dim_instructor (emp_id, full_name, designation, department_key)
    SELECT DISTINCT sis.instructor_emp_id, sis.instructor_name, 'Professor', dept.department_key
    FROM src_sis_academics sis
    JOIN dim_department dept ON sis.department_name = dept.department_code;

    -- Populate dim_course
    INSERT INTO dim_course (course_code, course_title, credit_hours, department_key, course_level)
    SELECT DISTINCT sis.course_code, sis.course_title, sis.credits, dept.department_key, 'Core'
    FROM src_sis_academics sis
    JOIN dim_department dept ON sis.department_name = dept.department_code;

    -- Semantic Entity Resolution for dim_student
    INSERT INTO dim_student (student_natural_id, admissions_app_no, official_email, full_name, admission_category, program_key, academic_status, scd_start_date, scd_end_date, is_current)
    SELECT 
        COALESCE(sis.enrollment_no, adm.app_id),
        adm.app_id,
        COALESCE(sis.official_email, adm.applicant_email),
        COALESCE(sis.full_name, adm.candidate_name),
        adm.admission_category,
        prog.program_key,
        'ACTIVE',
        '2023-08-01',
        '9999-12-31',
        1
    FROM src_admissions adm
    LEFT JOIN (
        SELECT DISTINCT enrollment_no, admissions_ref_no, full_name, official_email, program_id
        FROM src_sis_academics
    ) sis ON adm.app_id = sis.admissions_ref_no
    LEFT JOIN dim_program prog ON sis.program_id = prog.program_code;

    -- Load fact_course_enrollment_grades
    INSERT INTO fact_course_enrollment_grades (student_key, course_key, semester_key, instructor_key, credits_attempted, credits_earned, grade_points, total_grade_points, attendance_percentage, is_passed)
    SELECT 
        stu.student_key,
        crs.course_key,
        1,
        inst.instructor_key,
        sis.credits,
        CASE WHEN sis.grade_letter <> 'F' THEN sis.credits ELSE 0 END,
        sis.grade_points,
        (sis.credits * sis.grade_points),
        sis.attendance_percentage,
        CASE WHEN sis.grade_letter <> 'F' THEN 1 ELSE 0 END
    FROM src_sis_academics sis
    JOIN dim_student stu ON sis.enrollment_no = stu.student_natural_id
    JOIN dim_course crs ON sis.course_code = crs.course_code
    JOIN dim_instructor inst ON sis.instructor_emp_id = inst.emp_id;

    -- Load fact_lms_activity
    INSERT INTO fact_lms_activity (student_key, course_key, semester_key, total_logins_count, total_time_spent_minutes, assignments_submissions_count, quiz_attempts_count, avg_quiz_score_pct)
    SELECT 
        stu.student_key,
        crs.course_key,
        1,
        COUNT(lms.event_id),
        ROUND(SUM(COALESCE(lms.time_spent_seconds, 0)) / 60.0, 2),
        SUM(CASE WHEN lms.action_type = 'ASSIGNMENT_UPLOAD' THEN 1 ELSE 0 END),
        SUM(CASE WHEN lms.action_type = 'QUIZ_SUBMIT' THEN 1 ELSE 0 END),
        ROUND(AVG(CASE WHEN lms.max_score > 0 THEN (lms.score_obtained / lms.max_score) * 100 ELSE NULL END), 2)
    FROM src_lms_activity lms
    JOIN dim_student stu ON LOWER(lms.user_email) = LOWER(stu.official_email)
    JOIN dim_course crs ON lms.lms_course_code = crs.course_code
    GROUP BY stu.student_key, crs.course_key;

    -- Load fact_fee_transactions
    INSERT INTO fact_fee_transactions (txn_ref_id, student_key, fee_cat_key, semester_key, billed_amount, concession_amount, paid_amount, outstanding_balance)
    SELECT 
        fee.txn_ref_id,
        stu.student_key,
        1,
        1,
        fee.billed_amount,
        fee.concession_amount,
        fee.amount_paid,
        ((fee.billed_amount - fee.concession_amount) - fee.amount_paid)
    FROM src_fee_finance fee
    JOIN dim_student stu ON (fee.student_ident_val = stu.student_natural_id OR fee.student_ident_val = stu.admissions_app_no);

    -- Load fact_library_circulation
    INSERT INTO fact_library_circulation (student_key, asset_key, loan_duration_days, is_overdue, fine_assessed)
    SELECT 
        stu.student_key,
        lib.asset_key,
        14,
        CASE WHEN koha.fine_assessed > 0 THEN 1 ELSE 0 END,
        koha.fine_assessed
    FROM src_library_koha koha
    JOIN dim_student stu ON (koha.patron_card_no = stu.student_natural_id OR LOWER(koha.patron_email) = LOWER(stu.official_email))
    JOIN dim_library_asset lib ON koha.book_isbn = lib.isbn;

    -- Load fact_student_academic_360_monthly
    INSERT INTO fact_student_academic_360_monthly (student_key, current_gpa, avg_attendance_pct, monthly_lms_minutes, fee_dues_outstanding, is_academically_at_risk, is_financially_at_risk)
    SELECT 
        stu.student_key,
        ROUND(SUM(grd.total_grade_points) / NULLIF(SUM(grd.credits_attempted), 0), 2),
        ROUND(AVG(grd.attendance_percentage), 2),
        COALESCE(SUM(lms.total_time_spent_minutes), 0.0),
        COALESCE(MAX(fee.outstanding_balance), 0.0),
        CASE WHEN (SUM(grd.total_grade_points) / NULLIF(SUM(grd.credits_attempted), 0) < 6.0) OR (AVG(grd.attendance_percentage) < 75.0) THEN 1 ELSE 0 END,
        CASE WHEN COALESCE(MAX(fee.outstanding_balance), 0.0) > 0 THEN 1 ELSE 0 END
    FROM dim_student stu
    LEFT JOIN fact_course_enrollment_grades grd ON stu.student_key = grd.student_key
    LEFT JOIN fact_lms_activity lms ON stu.student_key = lms.student_key
    LEFT JOIN fact_fee_transactions fee ON stu.student_key = fee.student_key
    GROUP BY stu.student_key;
    """)

    conn.commit()
    return conn

conn = get_database_connection()

# Sidebar Navigation
with st.sidebar:
    st.image("https://img.icons8.com/fluency/96/database.png", width=64)
    st.markdown("### **Data Warehouse Portal**")
    st.markdown("**Subject:** Data Mining & Warehousing")
    st.markdown("**Guide:** **Mr. S. V. Swamy**")
    st.markdown("---")
    menu = st.radio(
        "Select Portal Module:",
        [
            "🏛️ System Architecture & Bus Matrix",
            "📥 Multi-Source Staging Explorer",
            "⚙️ Semantic Integration & ELT",
            "❄️ Star vs Snowflake Schemas",
            "📊 OLAP Analytics & Visualizations",
            "🚨 Student 360 Early Warning Mart",
            "📖 Academic Report & Viva Voce"
        ]
    )
    st.markdown("---")
    st.caption("Developed for University Data Warehouse Consolidation")

# ============================================================================
# MODULE 1: SYSTEM ARCHITECTURE & BUS MATRIX
# ============================================================================
if menu == "🏛️ System Architecture & Bus Matrix":
    st.markdown('<p class="main-title">Semantic Data Integration & Dimensional Warehouse</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Consolidating Admissions, Academics (SIS), LMS, Finance, and Library Systems</p>', unsafe_allow_html=True)
    st.markdown('<div class="mentor-badge">Project Mentor: Mr. S. V. Swamy</div>', unsafe_allow_html=True)

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Source Systems", "5 Silos", "Decentralized")
    with col2:
        st.metric("Kimball Dimensions", "9 Conformed", "SCD Type 2")
    with col3:
        st.metric("Fact Tables", "5 Core Facts", "Star & Snowflake")
    with col4:
        st.metric("Consolidated Mart", "Student 360°", "Early Warning")

    st.markdown("---")
    st.subheader("Enterprise Dimensional Bus Matrix")
    bus_matrix = pd.DataFrame({
        "Business Process / Fact Table": [
            "Academic Performance (fact_course_enrollment_grades)",
            "LMS Engagement (fact_lms_activity)",
            "Fee Collection (fact_fee_transactions)",
            "Library Circulation (fact_library_circulation)",
            "Student 360 Snapshot (fact_student_academic_360_monthly)"
        ],
        "dim_date": ["✅", "✅", "✅", "✅", "✅"],
        "dim_semester": ["✅", "✅", "✅", "➖", "✅"],
        "dim_student": ["✅", "✅", "✅", "✅", "✅"],
        "dim_course": ["✅", "✅", "➖", "➖", "➖"],
        "dim_instructor": ["✅", "➖", "➖", "➖", "➖"],
        "dim_department": ["✅ (via Prog)", "➖", "✅ (via Prog)", "➖", "✅ (via Prog)"],
        "dim_fee_cat": ["➖", "➖", "✅", "➖", "➖"],
        "dim_library_asset": ["➖", "➖", "➖", "✅", "➖"]
    })
    st.dataframe(bus_matrix, use_container_width=True, hide_index=True)

    st.markdown("---")
    st.subheader("Architectural Flow: From Staging to Analytical Marts")
    st.info("""
    1. **Staging Layer:** Ingests raw heterogeneous tables from MySQL (Admissions), Oracle (SIS), PostgreSQL (LMS), ERP (Finance), and MariaDB (Koha Library).
    2. **Semantic Integration Layer:** Performs entity resolution linking admissions application IDs, SIS university roll numbers, and LMS email addresses.
    3. **Dimensional Core (EDW):** Implements conformed dimensions with Kimball SCD Type 2 tracking and normalized Snowflake hierarchies (`College -> Department -> Program`).
    4. **Analytical Layer:** Delivers cross-domain OLAP queries and automated risk scores for proactive administrative intervention.
    """)

# ============================================================================
# MODULE 2: MULTI-SOURCE STAGING EXPLORER
# ============================================================================
elif menu == "📥 Multi-Source Staging Explorer":
    st.markdown('<p class="main-title">Heterogeneous Staging Sources</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Inspecting raw transactional data with real-world semantic mismatches</p>', unsafe_allow_html=True)
    st.markdown('<div class="mentor-badge">Project Mentor: Mr. S. V. Swamy</div>', unsafe_allow_html=True)

    source_tab = st.selectbox(
        "Choose Operational Source System:",
        ["1. Admissions Portal (src_admissions)", "2. SIS Academics (src_sis_academics)", "3. LMS Moodle (src_lms_activity)", "4. Fee ERP (src_fee_finance)", "5. Library Koha (src_library_koha)"]
    )

    if "src_admissions" in source_tab:
        st.write("**Extracted from Admissions Portal (Pre-enrollment applicants):**")
        df = pd.read_sql("SELECT * FROM src_admissions", conn)
        st.dataframe(df, use_container_width=True)
        st.warning("⚠️ **Semantic Challenge:** Natural Key is `app_id` (e.g. `APP-2023-0101`) and email is personal (`aarav.sharma@gmail.com`).")

    elif "src_sis_academics" in source_tab:
        st.write("**Extracted from Student Information System (Enrolled Coursework):**")
        df = pd.read_sql("SELECT * FROM src_sis_academics", conn)
        st.dataframe(df, use_container_width=True)
        st.info("💡 **Resolution:** SIS bridges `admissions_ref_no` with new university roll number `enrollment_no` and issues official university email (`aarav.s@univ.edu`).")

    elif "src_lms_activity" in source_tab:
        st.write("**Extracted from Learning Management System (Clickstream & Quiz Submissions):**")
        df = pd.read_sql("SELECT * FROM src_lms_activity", conn)
        st.dataframe(df, use_container_width=True)
        st.warning("⚠️ **Semantic Challenge:** User is only identified by email address (`user_email`), requiring join against conformed student email.")

    elif "src_fee_finance" in source_tab:
        st.write("**Extracted from Fee & Finance ERP:**")
        df = pd.read_sql("SELECT * FROM src_fee_finance", conn)
        st.dataframe(df, use_container_width=True)
        st.warning("⚠️ **Semantic Challenge:** Student identifier is heterogeneous: Admission fees use `APP-NO`, whereas subsequent term dues use `REG-NO`!")

    elif "src_library_koha" in source_tab:
        st.write("**Extracted from Koha Library Automation:**")
        df = pd.read_sql("SELECT * FROM src_library_koha", conn)
        st.dataframe(df, use_container_width=True)

# ============================================================================
# MODULE 3: SEMANTIC INTEGRATION & ELT
# ============================================================================
elif menu == "⚙️ Semantic Integration & ELT":
    st.markdown('<p class="main-title">Semantic Integration & Entity Resolution</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Automated reconciliation of disparate identifiers into Conformed Surrogate Keys</p>', unsafe_allow_html=True)
    st.markdown('<div class="mentor-badge">Project Mentor: Mr. S. V. Swamy</div>', unsafe_allow_html=True)

    st.subheader("1. Conformed Student Dimension (`dim_student`)")
    df_student = pd.read_sql("""
    SELECT 
        stu.student_key,
        stu.student_natural_id AS unified_roll_no,
        stu.admissions_app_no,
        stu.official_email,
        stu.full_name,
        prog.program_name,
        dept.department_code,
        stu.academic_status,
        stu.is_current
    FROM dim_student stu
    JOIN dim_program prog ON stu.program_key = prog.program_key
    JOIN dim_department dept ON prog.department_key = dept.department_key
    """, conn)
    st.dataframe(df_student, use_container_width=True)

    st.success("✅ **Entity Resolution Achieved:** Admissions Applicant IDs, SIS University Roll Numbers, and LMS official email addresses are successfully mapped into single conformed `student_key` surrogate keys with SCD Type 2 audit metadata.")

    st.markdown("---")
    st.subheader("2. Semantic SQL Transformation Code")
    st.code("""
-- Semantic Join resolving dual identifiers in Fee ERP
JOIN edw_dim.dim_student stu ON (
    fee.student_ident_val = stu.student_natural_id 
    OR fee.student_ident_val = stu.admissions_app_no
) AND stu.is_current = TRUE
    """, language="sql")

# ============================================================================
# MODULE 4: STAR VS SNOWFLAKE SCHEMAS
# ============================================================================
elif menu == "❄️ Star vs Snowflake Schemas":
    st.markdown('<p class="main-title">Star vs. Snowflake Schema Architecture</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Selective implementation of Normalized Hierarchies vs Denormalized Facts</p>', unsafe_allow_html=True)
    st.markdown('<div class="mentor-badge">Project Mentor: Mr. S. V. Swamy</div>', unsafe_allow_html=True)

    colA, colB = st.columns(2)
    with colA:
        st.subheader("❄️ Snowflake Dimension Hierarchy")
        st.markdown("**Normalized 3NF Structure:**")
        st.code("""
dim_school_college (college_key, college_name, dean_name)
       ↑ (FK)
dim_department (department_key, department_name, head_of_dept)
       ↑ (FK)
dim_program (program_key, program_name, degree_level)
       ↑ (FK)
dim_student (student_key, full_name, roll_no, email)
        """)
        st.caption("Benefits: Eliminates 3NF redundancy, allows updating college/dept dean with zero student-table cascades.")

    with colB:
        st.subheader("🌟 Pure Star Schema Fact Tables")
        st.markdown("**High-Speed OLAP Direct Links:**")
        st.code("""
fact_course_enrollment_grades
    ├── dim_student (FK)
    ├── dim_course (FK)
    ├── dim_instructor (FK)
    ├── dim_semester (FK)
    └── dim_date (FK)
        """)
        st.caption("Benefits: Minimum joins, maximum OLAP aggregation speed for complex analytic queries.")

    st.markdown("---")
    st.subheader("Interactive Snowflake Dimension Query")
    df_snow = pd.read_sql("""
    SELECT 
        col.college_name,
        col.dean_name,
        dept.department_name,
        dept.head_of_department,
        prog.program_name,
        prog.degree_level,
        COUNT(stu.student_key) AS enrolled_students_count
    FROM dim_school_college col
    JOIN dim_department dept ON col.college_key = dept.college_key
    JOIN dim_program prog ON dept.department_key = prog.department_key
    LEFT JOIN dim_student stu ON prog.program_key = stu.program_key
    GROUP BY col.college_name, col.dean_name, dept.department_name, dept.head_of_department, prog.program_name, prog.degree_level
    """, conn)
    st.dataframe(df_snow, use_container_width=True)

# ============================================================================
# MODULE 5: OLAP ANALYTICS & VISUALIZATIONS
# ============================================================================
elif menu == "📊 OLAP Analytics & Visualizations":
    st.markdown('<p class="main-title">Multi-Dimensional OLAP Analytics</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Roll-ups, Drill-downs, and Cross-Domain Behavioral Correlations</p>', unsafe_allow_html=True)
    st.markdown('<div class="mentor-badge">Project Mentor: Mr. S. V. Swamy</div>', unsafe_allow_html=True)

    tab1, tab2, tab3 = st.tabs(["📈 Cross-Domain Correlation", "🏛️ Academic Roll-up", "💰 Fee Collection Efficiency"])

    with tab1:
        st.subheader("Digital Engagement (LMS) vs Final Academic GPA")
        df_corr = pd.read_sql("""
        SELECT 
            stu.full_name,
            dept.department_code,
            ROUND(SUM(grd.total_grade_points) / NULLIF(SUM(grd.credits_attempted), 0), 2) AS gpa,
            ROUND(AVG(grd.attendance_percentage), 2) AS class_attendance_pct,
            COALESCE(SUM(lms.total_time_spent_minutes), 0.0) AS total_lms_minutes,
            COALESCE(SUM(lms.assignments_submissions_count + lms.quiz_attempts_count), 0) AS total_submissions
        FROM dim_student stu
        JOIN dim_program prog ON stu.program_key = prog.program_key
        JOIN dim_department dept ON prog.department_key = dept.department_key
        JOIN fact_course_enrollment_grades grd ON stu.student_key = grd.student_key
        LEFT JOIN fact_lms_activity lms ON stu.student_key = lms.student_key
        GROUP BY stu.student_key;
        """, conn)

        st.dataframe(df_corr, use_container_width=True)

        fig = px.scatter(
            df_corr,
            x="total_lms_minutes",
            y="gpa",
            size="class_attendance_pct",
            color="department_code",
            hover_name="full_name",
            title="LMS Time Spent (Minutes) vs Final Semester GPA (Bubble Size = Attendance %)",
            labels={"total_lms_minutes": "LMS Engagement (Minutes)", "gpa": "Grade Point Average (GPA)"}
        )
        st.plotly_chart(fig, use_container_width=True)

    with tab2:
        st.subheader("Departmental Academic Performance Roll-up")
        df_dept = pd.read_sql("""
        SELECT 
            dept.department_name,
            COUNT(DISTINCT grd.student_key) AS student_count,
            ROUND(AVG(grd.attendance_percentage), 2) AS avg_attendance,
            ROUND(SUM(grd.total_grade_points) / NULLIF(SUM(grd.credits_attempted), 0), 2) AS dept_avg_gpa,
            ROUND(SUM(CASE WHEN grd.is_passed = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pass_percentage
        FROM fact_course_enrollment_grades grd
        JOIN dim_student stu ON grd.student_key = stu.student_key
        JOIN dim_program prog ON stu.program_key = prog.program_key
        JOIN dim_department dept ON prog.department_key = dept.department_key
        GROUP BY dept.department_name
        """, conn)
        st.dataframe(df_dept, use_container_width=True)

        fig_bar = px.bar(
            df_dept,
            x="department_name",
            y="dept_avg_gpa",
            color="pass_percentage",
            title="Average GPA by Department (Color = Pass Percentage %)",
            text="dept_avg_gpa"
        )
        st.plotly_chart(fig_bar, use_container_width=True)

    with tab3:
        st.subheader("Fee Collection & Arrears Audit")
        df_fees = pd.read_sql("""
        SELECT 
            stu.full_name,
            stu.student_natural_id,
            stu.admission_category,
            fee.billed_amount,
            fee.concession_amount,
            fee.paid_amount,
            fee.outstanding_balance
        FROM fact_fee_transactions fee
        JOIN dim_student stu ON fee.student_key = stu.student_key
        """, conn)
        st.dataframe(df_fees, use_container_width=True)

# ============================================================================
# MODULE 6: STUDENT 360 EARLY WARNING MART
# ============================================================================
elif menu == "🚨 Student 360 Early Warning Mart":
    st.markdown('<p class="main-title">Student 360° Early Warning Mart</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Holistic cross-domain monitoring for early dropout & academic probation detection</p>', unsafe_allow_html=True)
    st.markdown('<div class="mentor-badge">Project Mentor: Mr. S. V. Swamy</div>', unsafe_allow_html=True)

    df_360 = pd.read_sql("""
    SELECT 
        stu.student_natural_id AS roll_number,
        stu.full_name,
        stu.official_email,
        dept.department_code,
        s360.current_gpa,
        s360.avg_attendance_pct,
        s360.monthly_lms_minutes,
        s360.fee_dues_outstanding,
        s360.is_academically_at_risk,
        s360.is_financially_at_risk
    FROM fact_student_academic_360_monthly s360
    JOIN dim_student stu ON s360.student_key = stu.student_key
    JOIN dim_program prog ON stu.program_key = prog.program_key
    JOIN dim_department dept ON prog.department_key = dept.department_key
    """, conn)

    for idx, row in df_360.iterrows():
        if row["is_academically_at_risk"] or row["is_financially_at_risk"]:
            st.error(f"""
            🚨 **CRITICAL INTERVENTION REQUIRED: {row['full_name']} ({row['roll_number']})**
            - **Department:** {row['department_code']} | **Email:** {row['official_email']}
            - **Current GPA:** `{row['current_gpa']}` (Threshold: < 6.0)
            - **Class Attendance:** `{row['avg_attendance_pct']}%` (Threshold: < 75%)
            - **LMS Engagement:** `{row['monthly_lms_minutes']} mins`
            - **Outstanding Fee Dues:** `₹{row['fee_dues_outstanding']:,.2f}`
            - **Action:** Academic probation counseling & Bursar financial aid review.
            """)
        else:
            st.success(f"""
            ✅ **GOOD ACADEMIC & FINANCIAL STANDING: {row['full_name']} ({row['roll_number']})**
            - **Department:** {row['department_code']} | **GPA:** `{row['current_gpa']}` | **Attendance:** `{row['avg_attendance_pct']}%`
            - **LMS Engagement:** `{row['monthly_lms_minutes']} mins` | **Dues:** `₹{row['fee_dues_outstanding']:,.2f}`
            """)

# ============================================================================
# MODULE 7: ACADEMIC REPORT & VIVA VOCE
# ============================================================================
elif menu == "📖 Academic Report & Viva Voce":
    st.markdown('<p class="main-title">Academic Project Report & Viva Defense</p>', unsafe_allow_html=True)
    st.markdown('<p class="sub-title">Complete dissertation text submitted for Data Mining & Warehousing</p>', unsafe_allow_html=True)
    st.markdown('<div class="mentor-badge">Project Mentor: Mr. S. V. Swamy</div>', unsafe_allow_html=True)

    report_path = os.path.join(os.path.dirname(__file__), "PROJECT_REPORT_DRAFT.md")
    if os.path.exists(report_path):
        with open(report_path, "r", encoding="utf-8") as f:
            report_text = f.read()
        st.markdown(report_text)
    else:
        st.info("Report file is available in the repository root.")
