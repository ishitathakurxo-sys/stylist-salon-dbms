-- =====================================================================
-- STYLIST SALON (MySQL 8.0)
-- File 2 of 5: PROCEDURES AND FUNCTIONS (all the app features)
-- Every value comes in as a parameter (bind variable). No SQL text is
-- ever glued together from user input, so SQL injection cannot work.
-- Result messages come back in the OUT parameter p_msg.
-- =====================================================================
USE stylist_salon;
DELIMITER $$

-- =====================================================================
-- FEATURE 1: USER MANAGEMENT
-- =====================================================================
CREATE PROCEDURE register_customer (
  IN p_name VARCHAR(50), IN p_phone VARCHAR(10), IN p_email VARCHAR(60),
  IN p_address VARCHAR(100), IN p_password VARCHAR(100), IN p_branch INT,
  OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE v_salt CHAR(16);
  DECLARE EXIT HANDLER FOR 1062
    SET p_msg = 'FAILED: this email is already registered';
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;

  IF CHAR_LENGTH(p_password) < 6 THEN
    SET v_err = 'Password must be at least 6 characters';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  SET v_salt = LEFT(SHA2(UUID(), 256), 16);          -- random salt
  INSERT INTO customer (name, phone, email, address, salt, password_hash, home_branch)
  VALUES (p_name, p_phone, p_email, p_address, v_salt,
          SHA2(CONCAT(v_salt, p_password), 256), p_branch);
  SET p_msg = CONCAT('OK: registered, customer id ', LAST_INSERT_ID());
END$$

-- Login: returns the customer id if email and password match, else 0
CREATE FUNCTION login_customer (p_email VARCHAR(60), p_password VARCHAR(100))
RETURNS INT READS SQL DATA
BEGIN
  DECLARE v_id INT DEFAULT 0;
  SELECT customer_id INTO v_id FROM customer
  WHERE email = p_email
    AND password_hash = SHA2(CONCAT(salt, p_password), 256)
  LIMIT 1;
  RETURN v_id;
END$$

CREATE PROCEDURE update_profile (
  IN p_id INT, IN p_name VARCHAR(50), IN p_phone VARCHAR(10), IN p_address VARCHAR(100),
  OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;
  UPDATE customer SET name = p_name, phone = p_phone, address = p_address
  WHERE customer_id = p_id;
  SET p_msg = 'OK: profile updated';
END$$

-- =====================================================================
-- FEATURE 2: SERVICE MANAGEMENT (admin) AND STAFF MANAGEMENT
-- =====================================================================
CREATE PROCEDURE add_service (
  IN p_name VARCHAR(40), IN p_category VARCHAR(20), IN p_price DECIMAL(8,2), IN p_duration INT,
  OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;
  INSERT INTO service (name, category, price, duration) VALUES (p_name, p_category, p_price, p_duration);
  SET p_msg = CONCAT('OK: service added, id ', LAST_INSERT_ID(), ' (copied to all 3 branches)');
END$$

CREATE PROCEDURE update_service (
  IN p_id INT, IN p_name VARCHAR(40), IN p_category VARCHAR(20), IN p_price DECIMAL(8,2), IN p_duration INT,
  OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;
  UPDATE service SET name = p_name, category = p_category, price = p_price, duration = p_duration
  WHERE service_id = p_id;
  SET p_msg = 'OK: service updated (copied to all 3 branches)';
END$$

-- "Remove" hides the service (active = 0). Old bills keep working.
CREATE PROCEDURE remove_service (IN p_id INT, OUT p_msg VARCHAR(200))
BEGIN
  UPDATE service SET active = 0 WHERE service_id = p_id;
  DELETE FROM cart_item WHERE service_id = p_id;
  SET p_msg = 'OK: service removed from the menu';
END$$

-- Search by name, category and price range. Pass NULL to skip a filter.
CREATE PROCEDURE search_services (
  IN p_name VARCHAR(40), IN p_category VARCHAR(20), IN p_min DECIMAL(8,2), IN p_max DECIMAL(8,2))
BEGIN
  SELECT service_id, name, category, price, duration
  FROM v_service_menu
  WHERE (p_name     IS NULL OR name LIKE CONCAT('%', p_name, '%'))
    AND (p_category IS NULL OR category = p_category)
    AND (p_min      IS NULL OR price >= p_min)
    AND (p_max      IS NULL OR price <= p_max)
  ORDER BY category, name;
END$$

CREATE PROCEDURE add_stylist (IN p_name VARCHAR(40), IN p_branch INT, OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;
  INSERT INTO stylist (name, branch_id) VALUES (p_name, p_branch);
  SET p_msg = CONCAT('OK: stylist added, id ', LAST_INSERT_ID());
END$$

CREATE PROCEDURE assign_service (IN p_stylist INT, IN p_service INT, OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;
  INSERT IGNORE INTO stylist_service VALUES (p_stylist, p_service);
  SET p_msg = 'OK: service assigned to stylist';
END$$

CREATE PROCEDURE unassign_service (IN p_stylist INT, IN p_service INT, OUT p_msg VARCHAR(200))
BEGIN
  DELETE FROM stylist_service WHERE stylist_id = p_stylist AND service_id = p_service;
  SET p_msg = 'OK: service un-assigned';
END$$

CREATE PROCEDURE deactivate_stylist (IN p_stylist INT, OUT p_msg VARCHAR(200))
BEGIN
  UPDATE stylist SET active = 0 WHERE stylist_id = p_stylist;
  SET p_msg = 'OK: stylist deactivated (old appointments are kept)';
END$$

-- =====================================================================
-- FEATURE 3: APPOINTMENT CART AND CHECKOUT
-- =====================================================================
CREATE PROCEDURE add_to_cart (IN p_customer INT, IN p_service INT, OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;
  IF NOT EXISTS (SELECT 1 FROM service WHERE service_id = p_service AND active = 1) THEN
    SET v_err = 'That service is not on the menu';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;
  INSERT IGNORE INTO cart_item VALUES (p_customer, p_service);
  SET p_msg = 'OK: added to cart';
END$$

-- Update the cart = swap one service for another
CREATE PROCEDURE update_cart (IN p_customer INT, IN p_old INT, IN p_new INT, OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    ROLLBACK;
    SET p_msg = CONCAT('FAILED: ', v_err);
  END;
  START TRANSACTION;
  IF NOT EXISTS (SELECT 1 FROM service WHERE service_id = p_new AND active = 1) THEN
    SET v_err = 'The new service is not on the menu';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;
  DELETE FROM cart_item WHERE customer_id = p_customer AND service_id = p_old;
  INSERT IGNORE INTO cart_item VALUES (p_customer, p_new);
  COMMIT;
  SET p_msg = 'OK: cart updated';
END$$

CREATE PROCEDURE remove_from_cart (IN p_customer INT, IN p_service INT, OUT p_msg VARCHAR(200))
BEGIN
  DELETE FROM cart_item WHERE customer_id = p_customer AND service_id = p_service;
  SET p_msg = 'OK: removed from cart';
END$$

CREATE PROCEDURE show_cart (IN p_customer INT)
BEGIN
  SELECT name AS service, price, duration AS minutes FROM v_cart WHERE customer_id = p_customer;
  SELECT COALESCE(SUM(price), 0) AS cart_total, COALESCE(SUM(duration), 0) AS total_minutes
  FROM v_cart WHERE customer_id = p_customer;
END$$

-- Free time slots for one stylist on one date
CREATE PROCEDURE available_slots (IN p_stylist INT, IN p_date DATE)
BEGIN
  SELECT t.slot AS free_slot
  FROM time_slot t
  WHERE NOT EXISTS (SELECT 1 FROM appointment_all a
                    WHERE a.stylist_id = p_stylist AND a.appt_date = p_date
                      AND a.slot = t.slot AND a.status <> 'Cancelled')
  ORDER BY t.slot;
END$$

-- CHECKOUT = ONE TRANSACTION (all or nothing):
--   appointment + its services + the payment + empty the cart.
-- Any problem -> ROLLBACK, nothing is saved, the cart stays as it was.
CREATE PROCEDURE checkout (
  IN p_customer INT, IN p_branch INT, IN p_stylist INT, IN p_date DATE, IN p_slot CHAR(5),
  OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_id    INT;
  DECLARE v_total DECIMAL(8,2);
  DECLARE v_items INT;
  DECLARE v_bad   INT;
  DECLARE v_err   VARCHAR(200);
  DECLARE EXIT HANDLER FOR 1062
  BEGIN
    ROLLBACK;
    SET p_msg = 'ROLLBACK: that stylist is already booked at that date and time. Nothing saved.';
  END;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    ROLLBACK;
    SET p_msg = CONCAT('ROLLBACK: ', v_err, '. Nothing saved.');
  END;

  START TRANSACTION;

  SELECT COUNT(*), COALESCE(SUM(price), 0) INTO v_items, v_total
  FROM v_cart WHERE customer_id = p_customer;
  IF v_items = 0 THEN
    SET v_err = 'Your cart is empty';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  IF p_date < CURDATE() THEN
    SET v_err = 'Cannot book a past date';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  -- does this stylist work at this branch AND do every service in the cart?
  SELECT COUNT(*) INTO v_bad
  FROM cart_item c
  WHERE c.customer_id = p_customer
    AND NOT EXISTS (SELECT 1 FROM stylist_service ss JOIN stylist st ON st.stylist_id = ss.stylist_id
                    WHERE ss.stylist_id = p_stylist AND st.branch_id = p_branch AND st.active = 1
                      AND ss.service_id = c.service_id);
  IF v_bad > 0 THEN
    SET v_err = 'Stylist is not at this branch or does not do every service in the cart';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  INSERT INTO appt_seq VALUES (NULL);
  SET v_id = LAST_INSERT_ID();

  -- Step 1: save the appointment in the right fragment
  IF p_branch = 1 THEN
    INSERT INTO appointment_downtown (appt_id, customer_id, stylist_id, appt_date, slot, total)
    VALUES (v_id, p_customer, p_stylist, p_date, p_slot, v_total);
  ELSEIF p_branch = 2 THEN
    INSERT INTO appointment_campus (appt_id, customer_id, stylist_id, appt_date, slot, total)
    VALUES (v_id, p_customer, p_stylist, p_date, p_slot, v_total);
  ELSEIF p_branch = 3 THEN
    INSERT INTO appointment_mall (appt_id, customer_id, stylist_id, appt_date, slot, total)
    VALUES (v_id, p_customer, p_stylist, p_date, p_slot, v_total);
  ELSE
    SET v_err = 'Unknown branch';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  -- Step 2: the services on the bill (price copied now)
  INSERT INTO appointment_item (appt_id, service_id, price)
  SELECT v_id, service_id, price FROM v_cart WHERE customer_id = p_customer;

  -- Step 3: the payment
  INSERT INTO payment (appt_id, amount) VALUES (v_id, v_total);

  -- Step 4: empty the cart
  DELETE FROM cart_item WHERE customer_id = p_customer;

  COMMIT;
  SET p_msg = CONCAT('COMMIT: appointment ', v_id, ' booked for ', p_date, ' ', p_slot, ', total Rs ', v_total);
END$$

-- =====================================================================
-- FEATURE 4: APPOINTMENT MANAGEMENT
-- =====================================================================
CREATE PROCEDURE my_appointments (IN p_customer INT)
BEGIN
  SELECT appt_id, branch, stylist, appt_date, slot, services, total, status, pay_status
  FROM v_appointment_history
  WHERE customer_id = p_customer
  ORDER BY appt_date DESC, slot;
END$$

-- Reschedule = move to a new date/slot (same branch and stylist)
CREATE PROCEDURE reschedule_appointment (
  IN p_id INT, IN p_date DATE, IN p_slot CHAR(5), OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_branch INT DEFAULT NULL;
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR 1062
  BEGIN
    ROLLBACK;
    SET p_msg = 'ROLLBACK: that stylist is already booked at the new time. Nothing changed.';
  END;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    ROLLBACK;
    SET p_msg = CONCAT('ROLLBACK: ', v_err, '. Nothing changed.');
  END;

  START TRANSACTION;
  SELECT branch_id, status INTO v_branch, v_status FROM appointment_all WHERE appt_id = p_id;
  IF v_branch IS NULL THEN
    SET v_err = 'Appointment not found';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;
  IF v_status <> 'Booked' THEN
    SET v_err = 'Only a Booked appointment can be rescheduled';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  IF v_branch = 1 THEN
    UPDATE appointment_downtown SET appt_date = p_date, slot = p_slot WHERE appt_id = p_id;
  ELSEIF v_branch = 2 THEN
    UPDATE appointment_campus   SET appt_date = p_date, slot = p_slot WHERE appt_id = p_id;
  ELSE
    UPDATE appointment_mall     SET appt_date = p_date, slot = p_slot WHERE appt_id = p_id;
  END IF;
  COMMIT;
  SET p_msg = CONCAT('COMMIT: appointment ', p_id, ' moved to ', p_date, ' ', p_slot);
END$$

-- Cancel: the id lives in exactly one fragment; the trigger writes the log.
CREATE PROCEDURE cancel_appointment (IN p_id INT, OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_status VARCHAR(12) DEFAULT NULL;
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    ROLLBACK;
    SET p_msg = CONCAT('ROLLBACK: ', v_err);
  END;

  START TRANSACTION;
  SELECT status INTO v_status FROM appointment_all WHERE appt_id = p_id;
  IF v_status IS NULL THEN
    SET v_err = 'Appointment not found';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;
  IF v_status <> 'Booked' THEN
    SET v_err = 'Only a Booked appointment can be cancelled';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  UPDATE appointment_downtown SET status = 'Cancelled' WHERE appt_id = p_id;
  UPDATE appointment_campus   SET status = 'Cancelled' WHERE appt_id = p_id;
  UPDATE appointment_mall     SET status = 'Cancelled' WHERE appt_id = p_id;
  UPDATE payment SET pay_status = 'Cancelled' WHERE appt_id = p_id;
  COMMIT;
  SET p_msg = CONCAT('COMMIT: appointment ', p_id, ' cancelled');
END$$

-- Status flow for stylist/admin: Booked -> In Progress -> Completed
CREATE PROCEDURE set_status (IN p_id INT, IN p_new VARCHAR(12), OUT p_msg VARCHAR(200))
BEGIN
  DECLARE v_old VARCHAR(12) DEFAULT NULL;
  DECLARE v_err VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
    ROLLBACK;
    SET p_msg = CONCAT('ROLLBACK: ', v_err);
  END;

  START TRANSACTION;
  SELECT status INTO v_old FROM appointment_all WHERE appt_id = p_id;
  IF v_old IS NULL THEN
    SET v_err = 'Appointment not found';
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;
  IF NOT ((v_old = 'Booked' AND p_new = 'In Progress')
       OR (v_old = 'In Progress' AND p_new = 'Completed')) THEN
    SET v_err = CONCAT('Cannot change status from ', v_old, ' to ', p_new);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err;
  END IF;

  UPDATE appointment_downtown SET status = p_new WHERE appt_id = p_id;
  UPDATE appointment_campus   SET status = p_new WHERE appt_id = p_id;
  UPDATE appointment_mall     SET status = p_new WHERE appt_id = p_id;
  IF p_new = 'Completed' THEN
    UPDATE payment SET pay_status = 'Paid', paid_on = NOW() WHERE appt_id = p_id;
  END IF;
  COMMIT;
  SET p_msg = CONCAT('COMMIT: appointment ', p_id, ' is now ', p_new);
END$$

-- =====================================================================
-- FEATURE 5: REPORTS  (+ QUERY PROCESSING)
-- =====================================================================
-- A global question ("total revenue of all branches") is split into one
-- small query per branch (each runs at ONE site). The answers are then
-- added up (GROUP BY ... WITH ROLLUP gives the global total row).
CREATE PROCEDURE report_revenue ()
BEGIN
  SELECT IF(GROUPING(site), 'GLOBAL TOTAL', site) AS site, SUM(revenue) AS revenue
  FROM (
    SELECT 'Downtown'    AS site, COALESCE(SUM(total), 0) AS revenue FROM appointment_downtown WHERE status <> 'Cancelled'
    UNION ALL
    SELECT 'Campus Road' AS site, COALESCE(SUM(total), 0) AS revenue FROM appointment_campus   WHERE status <> 'Cancelled'
    UNION ALL
    SELECT 'Mall Road'   AS site, COALESCE(SUM(total), 0) AS revenue FROM appointment_mall     WHERE status <> 'Cancelled'
  ) AS branch_answers
  GROUP BY site WITH ROLLUP;
END$$

DELIMITER ;
