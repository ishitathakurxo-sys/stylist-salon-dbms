-- =====================================================================
-- STYLIST SALON (MySQL 8.0)
-- File 3 of 5: DUMMY DATA
-- =====================================================================
USE stylist_salon;

INSERT INTO branch VALUES (1, 'Downtown'), (2, 'Campus Road'), (3, 'Mall Road');

INSERT INTO time_slot VALUES ('10:00'),('11:00'),('12:00'),('13:00'),('14:00'),('15:00'),('16:00'),('17:00');

INSERT INTO service (name, category, price, duration) VALUES
  ('Haircut',     'Hair',     300, 30),
  ('Hair spa',    'Hair',     800, 60),
  ('Hair colour', 'Hair',    1500, 90),
  ('Beard trim',  'Grooming', 150, 20),
  ('Shave',       'Grooming', 120, 20),
  ('Facial',      'Skin',     900, 45),
  ('Clean-up',    'Skin',     500, 30),
  ('Manicure',    'Nails',    450, 40);

INSERT INTO stylist (name, branch_id) VALUES
  ('Aman', 1), ('Neha', 1), ('Rohit', 2), ('Simran', 2), ('Karan', 3), ('Pooja', 3);

-- who can do what (same lists as the website)
INSERT INTO stylist_service (stylist_id, service_id)
  SELECT 1, service_id FROM service;                               -- Aman: everything
INSERT INTO stylist_service VALUES
  (2,1),(2,2),(2,3),(2,6),(2,7),(2,8),                             -- Neha
  (3,1),(3,2),(3,3),(3,4),(3,5),                                   -- Rohit
  (4,1),(4,2),(4,3),(4,6),(4,7),(4,8),                             -- Simran
  (5,1),(5,2),(5,3),(5,4),(5,5),                                   -- Karan
  (6,1),(6,2),(6,3),(6,6),(6,7),(6,8);                             -- Pooja

-- Customers, one admin and one stylist login (password for all: pass123)
CALL register_customer('Riya',  '9876543210', 'riya@mail.com',  'Downtown',    'pass123', 1, @m);
CALL register_customer('Arjun', '9876543211', 'arjun@mail.com', 'Campus Road', 'pass123', 2, @m);
CALL register_customer('Meera', '9876543212', 'meera@mail.com', 'Mall Road',   'pass123', 3, @m);
CALL register_customer('Dev',   '9876543213', 'dev@mail.com',   'Downtown',    'pass123', 1, @m);
CALL register_customer('Salon Admin', '9876500000', 'admin@salon.com', 'Head office', 'admin123', 1, @m);
CALL register_customer('Aman (stylist)', '9876500001', 'aman@salon.com', 'Downtown', 'style123', 1, @m);
UPDATE customer SET role = 'Admin'   WHERE email = 'admin@salon.com';
UPDATE customer SET role = 'Stylist' WHERE email = 'aman@salon.com';

-- ---------------------------------------------------------------------
-- Old and future appointments, so the reports have something to show.
-- The helper below is used only here and is dropped at the end.
-- (offset = days from today; negative = in the past)
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE PROCEDURE seed_appt (
  IN p_branch INT, IN p_customer INT, IN p_stylist INT, IN p_offset INT,
  IN p_slot CHAR(5), IN p_status VARCHAR(12), IN p_s1 INT, IN p_s2 INT)
BEGIN
  DECLARE v_id INT;
  DECLARE v_date DATE DEFAULT DATE_ADD(CURDATE(), INTERVAL p_offset DAY);
  DECLARE v_total DECIMAL(8,2);
  SET @seed_mode = 1;                                   -- lets the trigger accept old dates
  SELECT SUM(price) INTO v_total FROM service WHERE service_id IN (p_s1, COALESCE(p_s2, p_s1));
  INSERT INTO appt_seq VALUES (NULL);
  SET v_id = LAST_INSERT_ID();
  IF p_branch = 1 THEN
    INSERT INTO appointment_downtown (appt_id, customer_id, stylist_id, appt_date, slot, status, total)
    VALUES (v_id, p_customer, p_stylist, v_date, p_slot, p_status, v_total);
  ELSEIF p_branch = 2 THEN
    INSERT INTO appointment_campus (appt_id, customer_id, stylist_id, appt_date, slot, status, total)
    VALUES (v_id, p_customer, p_stylist, v_date, p_slot, p_status, v_total);
  ELSE
    INSERT INTO appointment_mall (appt_id, customer_id, stylist_id, appt_date, slot, status, total)
    VALUES (v_id, p_customer, p_stylist, v_date, p_slot, p_status, v_total);
  END IF;
  INSERT INTO appointment_item SELECT v_id, service_id, price FROM service WHERE service_id = p_s1;
  IF p_s2 IS NOT NULL THEN
    INSERT INTO appointment_item SELECT v_id, service_id, price FROM service WHERE service_id = p_s2;
  END IF;
  INSERT INTO payment (appt_id, amount, pay_status, paid_on)
  VALUES (v_id, v_total,
          CASE p_status WHEN 'Completed' THEN 'Paid' WHEN 'Cancelled' THEN 'Cancelled' ELSE 'Pending' END,
          IF(p_status = 'Completed', v_date, NULL));
  SET @seed_mode = NULL;
END$$
DELIMITER ;

--         branch cust stylist offset slot     status         service1 service2
CALL seed_appt(1, 1, 1, -40, '11:00', 'Completed',   1, 4);
CALL seed_appt(1, 4, 2, -35, '12:00', 'Completed',   2, NULL);
CALL seed_appt(2, 2, 3, -33, '10:00', 'Completed',   1, NULL);
CALL seed_appt(2, 2, 4, -20, '14:00', 'Completed',   6, 7);
CALL seed_appt(3, 3, 5, -18, '15:00', 'Completed',   3, NULL);
CALL seed_appt(3, 3, 6, -12, '11:00', 'Completed',   6, NULL);
CALL seed_appt(1, 1, 1,  -5, '11:00', 'Completed',   1, 5);
CALL seed_appt(2, 2, 3,  -3, '12:00', 'Completed',   1, NULL);
CALL seed_appt(3, 3, 6,  -2, '16:00', 'Cancelled',   2, NULL);
CALL seed_appt(1, 4, 2,   0, '13:00', 'In Progress', 8, NULL);
CALL seed_appt(2, 2, 4,   1, '11:00', 'Booked',      6, NULL);
CALL seed_appt(3, 3, 5,   2, '16:00', 'Booked',      1, 4);
CALL seed_appt(1, 1, 1,   3, '10:00', 'Booked',      1, NULL);

DROP PROCEDURE seed_appt;
