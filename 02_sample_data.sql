-- ============================================================================
-- SCRIPT 02: SAMPLE DATA POPULATION (MULTI-SOURCE HETEROGENEOUS DATA)
-- Project: Semantic Data Integration Across Multi-source Warehouses
-- Domain: University Data Warehouse Consolidation
-- ============================================================================

-- ============================================================================
-- 1. SEED DIMENSION METADATA (Colleges, Departments, Programs, Dates, Terms)
-- ============================================================================

-- Colleges (Snowflake root)
INSERT INTO edw_dim.dim_school_college (college_code, college_name, dean_name, building_location) VALUES
('ENG_COLLEGE', 'School of Engineering & Technology', 'Dr. Ramesh Rao', 'Tech Block A'),
('MGMT_COLLEGE', 'School of Business & Management', 'Dr. Sunita Kapoor', 'Management Tower B');

-- Departments (Snowflake level 2)
INSERT INTO edw_dim.dim_department (department_code, department_name, college_key, head_of_department) VALUES
('CSE', 'Computer Science & Engineering', 1, 'Dr. Anand Kumar'),
('ECE', 'Electronics & Communication Engineering', 1, 'Dr. Meena Iyer'),
('MBA', 'Management Studies', 2, 'Dr. Vikram Malhotra');

-- Programs (Snowflake level 3)
INSERT INTO edw_dim.dim_program (program_code, program_name, degree_level, duration_years, department_key) VALUES
('BTECH_CSE', 'Bachelor of Technology in Computer Science', 'Undergraduate', 4, 1),
('BTECH_ECE', 'Bachelor of Technology in Electronics', 'Undergraduate', 4, 2),
('MBA_GEN', 'Master of Business Administration', 'Postgraduate', 2, 3);

-- Semesters
INSERT INTO edw_dim.dim_semester (semester_code, academic_term, academic_year, start_date, end_date, is_current_term) VALUES
('SEM-2023-FALL', 'Fall', '2023-2024', '2023-08-01', '2023-12-20', FALSE),
('SEM-2024-SPRING', 'Spring', '2023-2024', '2024-01-10', '2024-05-25', TRUE);

-- Date Dimension (Sample Date Keys used in transactional logs)
INSERT INTO edw_dim.dim_date (date_key, full_date, calendar_day, calendar_month, month_name, calendar_quarter, quarter_name, calendar_year, is_weekend, academic_year) VALUES
(20230615, '2023-06-15', 15, 6, 'June', 2, 'Q2', 2023, FALSE, '2022-2023'),
(20230810, '2023-08-10', 10, 8, 'August', 3, 'Q3', 2023, FALSE, '2023-2024'),
(20230915, '2023-09-15', 15, 9, 'September', 3, 'Q3', 2023, FALSE, '2023-2024'),
(20231020, '2023-10-20', 20, 10, 'October', 4, 'Q4', 2023, FALSE, '2023-2024'),
(20231112, '2023-11-12', 12, 11, 'November', 4, 'Q4', 2023, TRUE, '2023-2024'),
(20231215, '2023-12-15', 15, 12, 'December', 4, 'Q4', 2023, FALSE, '2023-2024'),
(20240115, '2024-01-15', 15, 1, 'January', 1, 'Q1', 2024, FALSE, '2023-2024'),
(20240210, '2024-02-10', 10, 2, 'February', 1, 'Q1', 2024, FALSE, '2023-2024'),
(20240305, '2024-03-05', 5, 3, 'March', 1, 'Q1', 2024, FALSE, '2023-2024');

-- Fee Categories
INSERT INTO edw_dim.dim_fee_category (fee_type_code, fee_category_name, is_refundable) VALUES
('TUITION', 'Academic Tuition Fee', FALSE),
('HOSTEL', 'Hostel Accommodation & Mess', FALSE),
('LAB_EXAM', 'Laboratory & Examination Fee', FALSE),
('CAUTION_DEP', 'Refundable Caution Deposit', TRUE);

-- Library Assets
INSERT INTO edw_dim.dim_library_asset (isbn, title, subject_category, publisher, edition) VALUES
('978-0132350884', 'Clean Code: A Handbook of Agile Software Craftsmanship', 'Computer Science', 'Prentice Hall', '1st'),
('978-0262033848', 'Introduction to Algorithms', 'Computer Science / Algorithms', 'MIT Press', '3rd'),
('978-0134494166', 'Database System Concepts', 'Data Management', 'McGraw Hill', '7th'),
('978-0133856941', 'Marketing Management', 'Business Administration', 'Pearson', '15th');


-- ============================================================================
-- 2. HETEROGENEOUS STAGING DATA (Simulating Disparate Multi-Source Warehouses)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Source 1: Admissions Portal Staging
-- ----------------------------------------------------------------------------
INSERT INTO staging.src_admissions 
(app_id, candidate_name, applicant_email, phone_no, allocated_branch_code, entrance_exam_rank, admission_category, admission_status, allotment_date, application_fee_paid) 
VALUES
('APP-2023-0101', 'Aarav Sharma', 'aarav.sharma@gmail.com', '9876543210', 'CSE', 1240, 'Merit', 'CONFIRMED', '2023-06-15', 1500.00),
('APP-2023-0102', 'Priya Patel', 'priya.patel99@yahoo.com', '9876543211', 'CSE', 2410, 'Merit', 'CONFIRMED', '2023-06-16', 1500.00),
('APP-2023-0201', 'Rohan Verma', 'rohan.v@gmail.com', '9876543212', 'ECE', 3900, 'Management', 'CONFIRMED', '2023-06-20', 2500.00),
('APP-2023-0301', 'Sneha Reddy', 'sneha.reddy@outlook.com', '9876543213', 'MBA', 850, 'Merit', 'CONFIRMED', '2023-06-25', 2000.00),
('APP-2023-0999', 'Karan Johar', 'karan.j@gmail.com', '9876543299', 'CSE', 9800, 'Management', 'WITHDRAWN', '2023-07-01', 1500.00);

-- ----------------------------------------------------------------------------
-- Source 2: Student Information System (SIS) Academics Staging
-- (Notice: Admissions APP_NO is cross-referenced with new REG_NO; email is now official univ email)
-- ----------------------------------------------------------------------------
INSERT INTO staging.src_sis_academics 
(enrollment_no, admissions_ref_no, full_name, official_email, program_id, department_name, academic_term, course_code, course_title, instructor_emp_id, instructor_name, credits, grade_letter, grade_points, attendance_percentage) 
VALUES
-- Aarav Sharma - CS Courses
('REG-2023-CS-0101', 'APP-2023-0101', 'Aarav Sharma', 'aarav.s@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS301', 'Database Engineering & DW', 'EMP-CS-01', 'Dr. Anand Kumar', 4, 'A+', 10.00, 94.50),
('REG-2023-CS-0101', 'APP-2023-0101', 'Aarav Sharma', 'aarav.s@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS302', 'Data Structures & Algorithms', 'EMP-CS-02', 'Prof. Neha Gupta', 4, 'A', 9.00, 91.00),

-- Priya Patel - Struggling student (academic warning profile)
('REG-2023-CS-0102', 'APP-2023-0102', 'Priya Patel', 'priya.p@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS301', 'Database Engineering & DW', 'EMP-CS-01', 'Dr. Anand Kumar', 4, 'C', 5.00, 62.00),
('REG-2023-CS-0102', 'APP-2023-0102', 'Priya Patel', 'priya.p@univ.edu', 'BTECH_CSE', 'CSE', '2023-Fall', 'CS302', 'Data Structures & Algorithms', 'EMP-CS-02', 'Prof. Neha Gupta', 4, 'F', 0.00, 58.50),

-- Rohan Verma - ECE
('REG-2023-EC-0201', 'APP-2023-0201', 'Rohan Verma', 'rohan.v@univ.edu', 'BTECH_ECE', 'ECE', '2023-Fall', 'EC201', 'Signals & Linear Systems', 'EMP-EC-01', 'Dr. Meena Iyer', 4, 'B', 7.00, 84.00),

-- Sneha Reddy - MBA
('REG-2023-MB-0301', 'APP-2023-0301', 'Sneha Reddy', 'sneha.r@univ.edu', 'MBA_GEN', 'MBA', '2023-Fall', 'MB101', 'Strategic Marketing', 'EMP-MB-01', 'Dr. Vikram Malhotra', 3, 'A+', 10.00, 96.00);

-- ----------------------------------------------------------------------------
-- Source 3: LMS (Moodle / Canvas) Activity Logs Staging
-- (Notice: LMS identifies learners by official university email; dates in string format)
-- ----------------------------------------------------------------------------
INSERT INTO staging.src_lms_activity 
(event_id, user_email, lms_course_code, action_type, event_timestamp, time_spent_seconds, score_obtained, max_score) 
VALUES
-- High engagement student (Aarav Sharma)
('LMS-EVT-001', 'aarav.s@univ.edu', 'CS301', 'LECTURE_VIEW', '2023-09-15 10:15:00', 3600, NULL, NULL),
('LMS-EVT-002', 'aarav.s@univ.edu', 'CS301', 'QUIZ_SUBMIT', '2023-09-15 14:30:00', 1800, 19.5, 20.0),
('LMS-EVT-003', 'aarav.s@univ.edu', 'CS301', 'ASSIGNMENT_UPLOAD', '2023-10-20 23:10:00', 1200, 48.0, 50.0),
('LMS-EVT-004', 'aarav.s@univ.edu', 'CS302', 'FORUM_POST', '2023-10-20 16:45:00', 900, NULL, NULL),

-- Low engagement student (Priya Patel)
('LMS-EVT-005', 'priya.p@univ.edu', 'CS301', 'LECTURE_VIEW', '2023-09-15 11:00:00', 450, NULL, NULL),
('LMS-EVT-006', 'priya.p@univ.edu', 'CS301', 'QUIZ_SUBMIT', '2023-09-15 15:00:00', 600, 8.0, 20.0),

-- Rohan Verma
('LMS-EVT-007', 'rohan.v@univ.edu', 'EC201', 'ASSIGNMENT_UPLOAD', '2023-10-20 20:00:00', 2100, 38.0, 50.0),

-- Sneha Reddy
('LMS-EVT-008', 'sneha.r@univ.edu', 'MB101', 'FORUM_POST', '2023-10-20 09:30:00', 1500, NULL, NULL),
('LMS-EVT-009', 'sneha.r@univ.edu', 'MB101', 'QUIZ_SUBMIT', '2023-11-12 18:00:00', 2400, 19.0, 20.0);

-- ----------------------------------------------------------------------------
-- Source 4: Fee & Finance Management Staging
-- (Notice: Student identifier is heterogeneous: Admissions app_no for initial admission fee,
--  but registration roll_no for semester tuition fees!)
-- ----------------------------------------------------------------------------
INSERT INTO staging.src_fee_finance 
(txn_ref_id, student_ident_val, fee_type_code, term_period, billed_amount, concession_amount, amount_paid, payment_mode, payment_date, clearance_status) 
VALUES
-- Initial Admission fee (Linked via APP_NO)
('TXN-2023-F01', 'APP-2023-0101', 'TUITION', 'SEM-2023-FALL', 85000.00, 10000.00, 75000.00, 'NEFT', '2023-08-10', 'CLEARED'),
('TXN-2023-F02', 'APP-2023-0102', 'TUITION', 'SEM-2023-FALL', 85000.00, 0.00, 40000.00, 'UPI', '2023-08-10', 'PARTIAL'), -- Defaulter
('TXN-2023-F03', 'APP-2023-0201', 'TUITION', 'SEM-2023-FALL', 85000.00, 0.00, 85000.00, 'DEMAND_DRAFT', '2023-08-10', 'CLEARED'),
('TXN-2023-F04', 'APP-2023-0301', 'TUITION', 'SEM-2023-FALL', 120000.00, 20000.00, 100000.00, 'NEFT', '2023-08-10', 'CLEARED'),

-- Subsequent Semester Fee (Linked via REG_NO)
('TXN-2024-S01', 'REG-2023-CS-0101', 'TUITION', 'SEM-2024-SPRING', 85000.00, 10000.00, 75000.00, 'NEFT', '2024-01-15', 'CLEARED'),
('TXN-2024-S02', 'REG-2023-CS-0102', 'TUITION', 'SEM-2024-SPRING', 85000.00, 0.00, 0.00, 'NONE', '2024-01-15', 'UNPAID');

-- ----------------------------------------------------------------------------
-- Source 5: Koha Library Automation Staging
-- (Notice: Library identifies patrons through email address or patron card roll number)
-- ----------------------------------------------------------------------------
INSERT INTO staging.src_library_koha 
(issue_id, patron_card_no, patron_email, book_isbn, book_title, subject_category, checkout_date, due_date, return_date, fine_assessed, fine_collected) 
VALUES
('LIB-ISS-1001', 'REG-2023-CS-0101', 'aarav.s@univ.edu', '9876-0132350884', 'Clean Code', 'Computer Science', '2023-09-15', '2023-09-30', '2023-09-28', 0.00, 0.00),
('LIB-ISS-1002', 'REG-2023-CS-0101', 'aarav.s@univ.edu', '9876-0262033848', 'Introduction to Algorithms', 'Computer Science', '2023-10-20', '2023-11-05', '2023-11-04', 0.00, 0.00),
('LIB-ISS-1003', 'REG-2023-CS-0102', 'priya.p@univ.edu', '9876-0134494166', 'Database System Concepts', 'Data Management', '2023-10-20', '2023-11-05', '2023-12-15', 40.00, 0.00), -- Overdue return
('LIB-ISS-1004', 'REG-2023-MB-0301', 'sneha.r@univ.edu', '9876-0133856941', 'Marketing Management', 'Business Administration', '2023-11-12', '2023-11-27', '2023-11-25', 0.00, 0.00);
