-- =====================================================================
-- STYLIST SALON (MySQL 8.0)
-- File 4 of 5: DEMOS  (take a screenshot of each result for your report)
-- run.ps1 saves the full output to output\demo_output.txt
-- A few demos are MEANT to fail (rolled back or rejected). That is the point.
-- =====================================================================
USE stylist_salon;

-- ---------------------------------------------------------------------
SELECT '=== DEMO 1: USER MANAGEMENT (register, login, profile) ===' AS demo;
-- ---------------------------------------------------------------------
CALL register_customer('Kabir', '9000000001', 'kabir@mail.com', 'Mall Road', 'secret99', 3, @msg);
SELECT @msg AS result;
CALL register_customer('Kabir2', '9000000002', 'kabir@mail.com', 'Mall Road', 'secret99', 3, @msg);
SELECT @msg AS duplicate_email_result;
CALL register_customer('Bad Phone', '123', 'bad@mail.com', 'x', 'secret99', 1, @msg);
SELECT @msg AS bad_phone_result;

-- login: returns the customer id, or 0 when wrong
SELECT login_customer('riya@mail.com', 'pass123') AS right_password,
       login_customer('riya@mail.com', 'wrong')   AS wrong_password;

-- passwords are stored as salted hashes, never as text
SELECT customer_id, name, role, salt, password_hash FROM customer ORDER BY customer_id;

CALL update_profile(1, 'Riya Sharma', '9876543299', 'Downtown, Flat 4', @msg);
SELECT @msg AS result;
SELECT customer_id, name, phone, address FROM customer WHERE customer_id = 1;

-- ---------------------------------------------------------------------
SELECT '=== DEMO 2: SERVICE + STAFF MANAGEMENT (admin) ===' AS demo;
-- ---------------------------------------------------------------------
CALL search_services('hair', NULL, NULL, NULL);          -- by name
CALL search_services(NULL, 'Skin', NULL, NULL);          -- by category
CALL search_services(NULL, NULL, 200, 500);              -- by price range

CALL add_service('Head massage', 'Hair', 250, 25, @msg);   SELECT @msg AS result;
CALL add_service('Free service', 'Hair', -5, 10, @msg);    SELECT @msg AS bad_price_result;  -- CHECK blocks it
CALL update_service(9, 'Head massage', 'Hair', 275, 25, @msg);  SELECT @msg AS result;
-- the menu is REPLICATED: the same row now exists at all 3 sites
SELECT * FROM service_replica WHERE service_id = 9;
CALL remove_service(9, @msg);                              SELECT @msg AS result;
SELECT service_id, name, active FROM service WHERE service_id = 9;

CALL add_stylist('Isha', 2, @msg);   SELECT @msg AS result;
CALL assign_service(7, 1, @msg);     SELECT @msg AS result;
CALL assign_service(7, 6, @msg);     SELECT @msg AS result;
SELECT st.name AS stylist, b.branch_name AS branch, GROUP_CONCAT(sv.name ORDER BY sv.name) AS services
FROM stylist st
JOIN branch b ON b.branch_id = st.branch_id
LEFT JOIN stylist_service ss ON ss.stylist_id = st.stylist_id
LEFT JOIN service sv ON sv.service_id = ss.service_id
GROUP BY st.stylist_id, st.name, b.branch_name;

-- ---------------------------------------------------------------------
SELECT '=== DEMO 3: APPOINTMENT CART (add, update, remove) ===' AS demo;
-- ---------------------------------------------------------------------
CALL add_to_cart(1, 1, @msg);    -- Riya: Haircut
CALL add_to_cart(1, 5, @msg);    -- Riya: Shave
CALL add_to_cart(1, 99, @msg);   SELECT @msg AS unknown_service_result;
CALL show_cart(1);
CALL update_cart(1, 5, 4, @msg); SELECT @msg AS result;      -- swap Shave -> Beard trim
CALL show_cart(1);
CALL remove_from_cart(1, 4, @msg);
CALL add_to_cart(1, 4, @msg);    -- put Beard trim back
CALL show_cart(1);

-- ---------------------------------------------------------------------
SELECT '=== DEMO 4: CHECKOUT = ONE TRANSACTION (COMMIT / ROLLBACK) ===' AS demo;
-- ---------------------------------------------------------------------
CALL available_slots(1, DATE_ADD(CURDATE(), INTERVAL 1 DAY));      -- Aman, tomorrow

-- 4a. OK: Riya books Haircut + Beard trim with Aman, Downtown, tomorrow 11:00
CALL checkout(1, 1, 1, DATE_ADD(CURDATE(), INTERVAL 1 DAY), '11:00', @msg);
SELECT @msg AS booking_1;

-- 4b. CLASH: Dev wants the same stylist, same date, same slot -> ROLLBACK
CALL add_to_cart(4, 2, @msg);
CALL checkout(4, 1, 1, DATE_ADD(CURDATE(), INTERVAL 1 DAY), '11:00', @msg);
SELECT @msg AS booking_2_clash;
CALL show_cart(4);               -- cart is untouched: nothing was saved

-- 4c. Dev books a free slot instead
CALL checkout(4, 1, 1, DATE_ADD(CURDATE(), INTERVAL 1 DAY), '12:00', @msg);
SELECT @msg AS booking_3;

-- 4d. Other branches (each saved in its own fragment)
CALL add_to_cart(2, 2, @msg);
CALL checkout(2, 2, 3, DATE_ADD(CURDATE(), INTERVAL 1 DAY), '12:00', @msg);
SELECT @msg AS booking_campus;
CALL add_to_cart(3, 3, @msg);
CALL checkout(3, 3, 5, DATE_ADD(CURDATE(), INTERVAL 2 DAY), '15:00', @msg);
SELECT @msg AS booking_mall;

-- 4e. PAST DATE: the procedure (and the trigger) block it
CALL add_to_cart(3, 1, @msg);
CALL checkout(3, 3, 5, DATE_SUB(CURDATE(), INTERVAL 1 DAY), '10:00', @msg);
SELECT @msg AS past_date_result;

-- 4f. WRONG BRANCH: Aman works at Downtown, not at Campus Road
CALL checkout(3, 2, 1, DATE_ADD(CURDATE(), INTERVAL 3 DAY), '14:00', @msg);
SELECT @msg AS wrong_branch_result;

-- 4g. FRAGMENT RULE (trigger): a Downtown stylist cannot be inserted into the Campus fragment
INSERT INTO appointment_campus (appt_id, customer_id, stylist_id, appt_date, slot, total)
VALUES (9999, 1, 1, DATE_ADD(CURDATE(), INTERVAL 5 DAY), '10:00', 100);   -- ERROR expected
CALL remove_from_cart(3, 1, @msg);

-- ---------------------------------------------------------------------
SELECT '=== DEMO 5: HISTORY, RESCHEDULE, STATUS, CANCEL (+ trigger log) ===' AS demo;
-- ---------------------------------------------------------------------
CALL my_appointments(1);                                   -- Riya's history

-- reschedule Dev's booking (find its id from history first)
SET @dev_appt = (SELECT MAX(appt_id) FROM appointment_all WHERE customer_id = 4 AND status = 'Booked');
CALL reschedule_appointment(@dev_appt, DATE_ADD(CURDATE(), INTERVAL 4 DAY), '15:00', @msg);
SELECT @msg AS reschedule_ok;
-- reschedule into a slot that is taken -> ROLLBACK
SET @riya_appt = (SELECT MAX(appt_id) FROM appointment_all WHERE customer_id = 1 AND status = 'Booked');
CALL reschedule_appointment(@dev_appt, DATE_ADD(CURDATE(), INTERVAL 1 DAY), '11:00', @msg);
SELECT @msg AS reschedule_clash;

-- status flow: Booked -> In Progress -> Completed (payment becomes Paid)
CALL set_status(@riya_appt, 'Completed', @msg);   SELECT @msg AS skipping_a_step;
CALL set_status(@riya_appt, 'In Progress', @msg); SELECT @msg AS step_1;
CALL set_status(@riya_appt, 'Completed', @msg);   SELECT @msg AS step_2;
SELECT appt_id, status, total, pay_status FROM v_appointment_history WHERE appt_id = @riya_appt;

-- cancel frees the slot and the trigger writes the log
CALL cancel_appointment(@dev_appt, @msg);         SELECT @msg AS cancel_result;
CALL cancel_appointment(@riya_appt, @msg);        SELECT @msg AS cancel_completed_result;   -- refused
SELECT * FROM cancel_log;

-- ---------------------------------------------------------------------
SELECT '=== DEMO 6: DISTRIBUTED DATABASE (fragmentation, allocation, dictionary) ===' AS demo;
-- ---------------------------------------------------------------------
SELECT 'Downtown' AS site, COUNT(*) AS rows_stored FROM appointment_downtown
UNION ALL SELECT 'Campus Road', COUNT(*) FROM appointment_campus
UNION ALL SELECT 'Mall Road',   COUNT(*) FROM appointment_mall;
SELECT * FROM data_dictionary;
-- the global view hides the fragments: one table to the user
SELECT branch_id, appt_id, stylist_id, appt_date, slot, status, total FROM appointment_all ORDER BY appt_date, slot;

-- ---------------------------------------------------------------------
SELECT '=== DEMO 7: QUERY PROCESSING (global query -> branch queries) ===' AS demo;
-- ---------------------------------------------------------------------
-- Step 1: branch-level queries (each runs at ONE site)
SELECT 'Downtown' AS site, COALESCE(SUM(total), 0) AS revenue FROM appointment_downtown WHERE status <> 'Cancelled'
UNION ALL
SELECT 'Campus Road', COALESCE(SUM(total), 0) FROM appointment_campus WHERE status <> 'Cancelled'
UNION ALL
SELECT 'Mall Road',   COALESCE(SUM(total), 0) FROM appointment_mall   WHERE status <> 'Cancelled';
-- Step 2: the global question, answered by adding the branch answers
SELECT SUM(total) AS total_revenue_all_branches FROM appointment_all WHERE status <> 'Cancelled';
-- Same thing as one procedure (branch answers + GLOBAL TOTAL row)
CALL report_revenue();
-- How MySQL itself splits the global query: one scan per fragment, then combine
EXPLAIN FORMAT=TREE SELECT SUM(total) FROM appointment_all WHERE status <> 'Cancelled';

-- ---------------------------------------------------------------------
SELECT '=== DEMO 8: REPORTS ===' AS demo;
-- ---------------------------------------------------------------------
SELECT * FROM rpt_most_booked_service ORDER BY times_booked DESC;
SELECT * FROM rpt_busiest_hours       ORDER BY bookings DESC, time_slot;
SELECT * FROM rpt_stylist_bookings    ORDER BY bookings DESC, stylist;
SELECT * FROM rpt_daily_revenue       ORDER BY day;
SELECT * FROM rpt_monthly_revenue     ORDER BY month;
SELECT * FROM rpt_branch_revenue      ORDER BY branch;

-- ---------------------------------------------------------------------
SELECT '=== DEMO 9: TRANSACTIONS, ACID, RECOVERY ===' AS demo;
-- ---------------------------------------------------------------------
-- ATOMICITY + RECOVERY: an uncommitted change is undone by ROLLBACK
SELECT COUNT(*) AS before_count FROM service;
START TRANSACTION;
INSERT INTO service (name, category, price, duration) VALUES ('Test service', 'Hair', 100, 10);
SELECT COUNT(*) AS during_count FROM service;      -- one more
ROLLBACK;
SELECT COUNT(*) AS after_rollback FROM service;    -- back to the original

-- A SAVEPOINT undoes only part of a transaction
START TRANSACTION;
INSERT INTO service (name, category, price, duration) VALUES ('Keep me', 'Hair', 100, 10);
SAVEPOINT after_first;
INSERT INTO service (name, category, price, duration) VALUES ('Drop me', 'Hair', 100, 10);
ROLLBACK TO after_first;
COMMIT;
SELECT name FROM service WHERE name IN ('Keep me', 'Drop me');   -- only "Keep me"
DELETE FROM service WHERE name = 'Keep me';

-- CONSISTENCY: the database refuses data that breaks its rules (each of these FAILS)
INSERT INTO service (name, category, price, duration) VALUES ('Bad price', 'Hair', -5, 10);     -- CHECK price > 0
INSERT INTO customer (name, phone, email, salt, password_hash) VALUES ('X', '12', 'x@x.com', 's', 'h');  -- CHECK phone
INSERT INTO stylist (name, branch_id) VALUES ('Ghost', 99);                                    -- FOREIGN KEY

-- DURABILITY + WRITE-AHEAD LOGGING (InnoDB writes the redo log BEFORE the data file)
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';   -- 1 = log is flushed to disk at every COMMIT
SHOW VARIABLES LIKE 'innodb_redo_log_capacity';
SHOW GLOBAL STATUS LIKE 'Innodb_os_log_written';        -- bytes written to the log so far
START TRANSACTION;
UPDATE service SET price = price + 1 WHERE service_id = 1;
COMMIT;
SHOW GLOBAL STATUS LIKE 'Innodb_os_log_written';        -- the number went up: the log was written at COMMIT
UPDATE service SET price = price - 1 WHERE service_id = 1;

-- ---------------------------------------------------------------------
SELECT '=== DEMO 10: SECURITY (SQL injection, bind variables) ===' AS demo;
-- ---------------------------------------------------------------------
-- The classic attack text is treated as plain text, so login fails (0 = no match)
SELECT login_customer('x'' OR ''1''=''1', 'x'' OR ''1''=''1') AS injection_attempt;
-- Prepared statement: the ? is a bind variable, the value can never become SQL
SET @e = 'riya@mail.com';
PREPARE stmt FROM 'SELECT customer_id, name FROM customer WHERE email = ?';
EXECUTE stmt USING @e;
DEALLOCATE PREPARE stmt;
