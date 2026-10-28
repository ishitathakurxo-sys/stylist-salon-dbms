-- =====================================================================
-- STYLIST SALON: Online Appointment Booking System  (MySQL 8.0)
-- File 1 of 5: TABLES, VIEWS, TRIGGERS, DATA DICTIONARY
-- Run with run.ps1, or in MySQL Workbench: open the file and press the
-- lightning button. Running it again wipes and rebuilds the database.
-- =====================================================================
DROP DATABASE IF EXISTS stylist_salon;
CREATE DATABASE stylist_salon CHARACTER SET utf8mb4;
USE stylist_salon;

-- ---------------------------------------------------------------------
-- PART 1: TABLES (normalized to 3NF)
-- ---------------------------------------------------------------------
CREATE TABLE branch (
  branch_id   TINYINT     PRIMARY KEY,
  branch_name VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE time_slot (
  slot CHAR(5) PRIMARY KEY
);

CREATE TABLE service (
  service_id INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(40)  NOT NULL,
  category   VARCHAR(20)  NOT NULL,
  price      DECIMAL(8,2) NOT NULL CHECK (price > 0),
  duration   INT          NOT NULL CHECK (duration > 0),
  active     TINYINT(1)   NOT NULL DEFAULT 1      -- 0 = removed from the menu
);

CREATE TABLE stylist (
  stylist_id INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(40) NOT NULL,
  branch_id  TINYINT     NOT NULL,
  active     TINYINT(1)  NOT NULL DEFAULT 1,
  FOREIGN KEY (branch_id) REFERENCES branch (branch_id)
);

CREATE TABLE stylist_service (
  stylist_id INT,
  service_id INT,
  PRIMARY KEY (stylist_id, service_id),
  FOREIGN KEY (stylist_id) REFERENCES stylist (stylist_id),
  FOREIGN KEY (service_id) REFERENCES service (service_id)
);

-- One table for all people; "role" decides what they may do.
CREATE TABLE customer (
  customer_id   INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(50) NOT NULL,
  phone         CHAR(10)    NOT NULL CHECK (phone REGEXP '^[0-9]{10}$'),
  email         VARCHAR(60) NOT NULL UNIQUE,
  address       VARCHAR(100),
  salt          CHAR(16)    NOT NULL,             -- random text added before hashing
  password_hash CHAR(64)    NOT NULL,             -- SHA-256, never the real password
  role          ENUM('Customer','Stylist','Admin') NOT NULL DEFAULT 'Customer',
  home_branch   TINYINT,
  FOREIGN KEY (home_branch) REFERENCES branch (branch_id)
);

-- The appointment cart: services chosen but not yet booked.
CREATE TABLE cart_item (
  customer_id INT,
  service_id  INT,
  PRIMARY KEY (customer_id, service_id),
  FOREIGN KEY (customer_id) REFERENCES customer (customer_id),
  FOREIGN KEY (service_id)  REFERENCES service (service_id)
);

-- MySQL has no SEQUENCE, so this tiny table hands out appointment ids
-- that are unique across ALL branches.
CREATE TABLE appt_seq (
  appt_id INT AUTO_INCREMENT PRIMARY KEY
);

-- APPOINTMENT is horizontally fragmented: one table per branch.
-- active_key is "stylist|date|slot" while the booking is alive and NULL
-- once cancelled. UNIQUE on it = no double booking, and a cancelled
-- booking frees the slot (NULLs never clash in a UNIQUE index).
CREATE TABLE appointment_downtown (
  appt_id     INT PRIMARY KEY,
  customer_id INT NOT NULL,
  stylist_id  INT NOT NULL,
  appt_date   DATE NOT NULL,
  slot        CHAR(5) NOT NULL,
  status      ENUM('Booked','In Progress','Completed','Cancelled') NOT NULL DEFAULT 'Booked',
  total       DECIMAL(8,2) NOT NULL,
  active_key  VARCHAR(40) GENERATED ALWAYS AS
              (IF(status = 'Cancelled', NULL, CONCAT(stylist_id, '|', appt_date, '|', slot))) STORED,
  UNIQUE KEY ux_slot (active_key),
  FOREIGN KEY (customer_id) REFERENCES customer (customer_id),
  FOREIGN KEY (stylist_id)  REFERENCES stylist (stylist_id),
  FOREIGN KEY (slot)        REFERENCES time_slot (slot)
);

CREATE TABLE appointment_campus (
  appt_id     INT PRIMARY KEY,
  customer_id INT NOT NULL,
  stylist_id  INT NOT NULL,
  appt_date   DATE NOT NULL,
  slot        CHAR(5) NOT NULL,
  status      ENUM('Booked','In Progress','Completed','Cancelled') NOT NULL DEFAULT 'Booked',
  total       DECIMAL(8,2) NOT NULL,
  active_key  VARCHAR(40) GENERATED ALWAYS AS
              (IF(status = 'Cancelled', NULL, CONCAT(stylist_id, '|', appt_date, '|', slot))) STORED,
  UNIQUE KEY ux_slot (active_key),
  FOREIGN KEY (customer_id) REFERENCES customer (customer_id),
  FOREIGN KEY (stylist_id)  REFERENCES stylist (stylist_id),
  FOREIGN KEY (slot)        REFERENCES time_slot (slot)
);

CREATE TABLE appointment_mall (
  appt_id     INT PRIMARY KEY,
  customer_id INT NOT NULL,
  stylist_id  INT NOT NULL,
  appt_date   DATE NOT NULL,
  slot        CHAR(5) NOT NULL,
  status      ENUM('Booked','In Progress','Completed','Cancelled') NOT NULL DEFAULT 'Booked',
  total       DECIMAL(8,2) NOT NULL,
  active_key  VARCHAR(40) GENERATED ALWAYS AS
              (IF(status = 'Cancelled', NULL, CONCAT(stylist_id, '|', appt_date, '|', slot))) STORED,
  UNIQUE KEY ux_slot (active_key),
  FOREIGN KEY (customer_id) REFERENCES customer (customer_id),
  FOREIGN KEY (stylist_id)  REFERENCES stylist (stylist_id),
  FOREIGN KEY (slot)        REFERENCES time_slot (slot)
);

-- One appointment can hold many services (the cart). The price is copied
-- at booking time so later price changes do not change old bills.
-- No FK to the appointment tables: the parent row lives in one of 3 fragments.
CREATE TABLE appointment_item (
  appt_id    INT,
  service_id INT,
  price      DECIMAL(8,2) NOT NULL,
  PRIMARY KEY (appt_id, service_id),
  FOREIGN KEY (service_id) REFERENCES service (service_id)
);

CREATE TABLE payment (
  appt_id    INT PRIMARY KEY,
  amount     DECIMAL(8,2) NOT NULL,
  pay_status ENUM('Pending','Paid','Cancelled') NOT NULL DEFAULT 'Pending',
  paid_on    DATETIME NULL
);

CREATE TABLE cancel_log (
  log_id       INT AUTO_INCREMENT PRIMARY KEY,
  appt_id      INT,
  cancelled_on DATETIME,
  branch_name  VARCHAR(30)
);

-- ---------------------------------------------------------------------
-- PART 2: DISTRIBUTED DESIGN (global view, replication, data dictionary)
-- ---------------------------------------------------------------------
-- Global view: makes the three fragments look like ONE table.
CREATE VIEW appointment_all AS
  SELECT 1 AS branch_id, appt_id, customer_id, stylist_id, appt_date, slot, status, total FROM appointment_downtown
  UNION ALL
  SELECT 2, appt_id, customer_id, stylist_id, appt_date, slot, status, total FROM appointment_campus
  UNION ALL
  SELECT 3, appt_id, customer_id, stylist_id, appt_date, slot, status, total FROM appointment_mall;

-- Replication: the service menu is copied to every branch (site).
-- Triggers keep the copies in step with the master SERVICE table.
CREATE TABLE service_replica (
  site       TINYINT,
  service_id INT,
  name       VARCHAR(40),
  category   VARCHAR(20),
  price      DECIMAL(8,2),
  duration   INT,
  active     TINYINT(1),
  PRIMARY KEY (site, service_id)
);

CREATE TABLE data_dictionary (
  table_name         VARCHAR(30),
  fragment_type      VARCHAR(40),
  fragmentation_rule VARCHAR(60),
  stored_at          VARCHAR(40)
);
INSERT INTO data_dictionary VALUES
 ('appointment_downtown','Horizontal fragment','stylist.branch_id = 1','Downtown site only'),
 ('appointment_campus',  'Horizontal fragment','stylist.branch_id = 2','Campus Road site only'),
 ('appointment_mall',    'Horizontal fragment','stylist.branch_id = 3','Mall Road site only'),
 ('appointment_all',     'Global view (UNION ALL)','union of the 3 fragments','Any site (virtual)'),
 ('service',             'Replicated','full copy at every site','All 3 sites (service_replica)'),
 ('branch / time_slot',  'Replicated','full copy at every site','All 3 sites'),
 ('stylist',             'Allocated by branch_id','stylist.branch_id','Own branch site'),
 ('customer',            'Logical split by home_branch','customer.home_branch','Home branch site'),
 ('payment, appointment_item','Allocated with their appointment','appt_id','Same site as the appointment');

-- ---------------------------------------------------------------------
-- PART 3: TRIGGERS (active database)
-- ---------------------------------------------------------------------
DELIMITER $$

-- Replication triggers
CREATE TRIGGER trg_service_ai AFTER INSERT ON service FOR EACH ROW
BEGIN
  REPLACE INTO service_replica
  SELECT b.branch_id, NEW.service_id, NEW.name, NEW.category, NEW.price, NEW.duration, NEW.active
  FROM branch b;
END$$

CREATE TRIGGER trg_service_au AFTER UPDATE ON service FOR EACH ROW
BEGIN
  REPLACE INTO service_replica
  SELECT b.branch_id, NEW.service_id, NEW.name, NEW.category, NEW.price, NEW.duration, NEW.active
  FROM branch b;
END$$

-- Fragment triggers. Three per branch:
--   BEFORE INSERT: block past dates + make sure the stylist belongs to this branch
--   BEFORE UPDATE: block moving an appointment into the past
--   AFTER  UPDATE: write a row in cancel_log when a booking is cancelled
-- (@seed_mode is set only by the seed script, to load old history.)

-- ----- Downtown (branch 1)
CREATE TRIGGER trg_bi_downtown BEFORE INSERT ON appointment_downtown FOR EACH ROW
BEGIN
  IF NEW.appt_date < CURDATE() AND @seed_mode IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot book a past date';
  END IF;
  IF (SELECT branch_id FROM stylist WHERE stylist_id = NEW.stylist_id) <> 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fragment rule: this stylist does not belong to Downtown';
  END IF;
END$$
CREATE TRIGGER trg_bu_downtown BEFORE UPDATE ON appointment_downtown FOR EACH ROW
BEGIN
  IF NEW.appt_date <> OLD.appt_date AND NEW.appt_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot move an appointment to a past date';
  END IF;
END$$
CREATE TRIGGER trg_au_downtown AFTER UPDATE ON appointment_downtown FOR EACH ROW
BEGIN
  IF NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled' THEN
    INSERT INTO cancel_log (appt_id, cancelled_on, branch_name) VALUES (OLD.appt_id, NOW(), 'Downtown');
  END IF;
END$$

-- ----- Campus Road (branch 2)
CREATE TRIGGER trg_bi_campus BEFORE INSERT ON appointment_campus FOR EACH ROW
BEGIN
  IF NEW.appt_date < CURDATE() AND @seed_mode IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot book a past date';
  END IF;
  IF (SELECT branch_id FROM stylist WHERE stylist_id = NEW.stylist_id) <> 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fragment rule: this stylist does not belong to Campus Road';
  END IF;
END$$
CREATE TRIGGER trg_bu_campus BEFORE UPDATE ON appointment_campus FOR EACH ROW
BEGIN
  IF NEW.appt_date <> OLD.appt_date AND NEW.appt_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot move an appointment to a past date';
  END IF;
END$$
CREATE TRIGGER trg_au_campus AFTER UPDATE ON appointment_campus FOR EACH ROW
BEGIN
  IF NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled' THEN
    INSERT INTO cancel_log (appt_id, cancelled_on, branch_name) VALUES (OLD.appt_id, NOW(), 'Campus Road');
  END IF;
END$$

-- ----- Mall Road (branch 3)
CREATE TRIGGER trg_bi_mall BEFORE INSERT ON appointment_mall FOR EACH ROW
BEGIN
  IF NEW.appt_date < CURDATE() AND @seed_mode IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot book a past date';
  END IF;
  IF (SELECT branch_id FROM stylist WHERE stylist_id = NEW.stylist_id) <> 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fragment rule: this stylist does not belong to Mall Road';
  END IF;
END$$
CREATE TRIGGER trg_bu_mall BEFORE UPDATE ON appointment_mall FOR EACH ROW
BEGIN
  IF NEW.appt_date <> OLD.appt_date AND NEW.appt_date < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot move an appointment to a past date';
  END IF;
END$$
CREATE TRIGGER trg_au_mall AFTER UPDATE ON appointment_mall FOR EACH ROW
BEGIN
  IF NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled' THEN
    INSERT INTO cancel_log (appt_id, cancelled_on, branch_name) VALUES (OLD.appt_id, NOW(), 'Mall Road');
  END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- PART 4: REPORT VIEWS (revenue = every appointment that is not Cancelled)
-- ---------------------------------------------------------------------
CREATE VIEW rpt_most_booked_service AS
  SELECT sv.name AS service, COUNT(*) AS times_booked
  FROM appointment_item i
  JOIN appointment_all a ON a.appt_id = i.appt_id AND a.status <> 'Cancelled'
  JOIN service sv        ON sv.service_id = i.service_id
  GROUP BY sv.name;

CREATE VIEW rpt_busiest_hours AS
  SELECT slot AS time_slot, COUNT(*) AS bookings
  FROM appointment_all WHERE status <> 'Cancelled'
  GROUP BY slot;

CREATE VIEW rpt_stylist_bookings AS
  SELECT st.name AS stylist, b.branch_name AS branch, COUNT(*) AS bookings, SUM(a.total) AS revenue
  FROM appointment_all a
  JOIN stylist st ON st.stylist_id = a.stylist_id
  JOIN branch b   ON b.branch_id = st.branch_id
  WHERE a.status <> 'Cancelled'
  GROUP BY st.name, b.branch_name;

CREATE VIEW rpt_daily_revenue AS
  SELECT appt_date AS day, SUM(total) AS revenue
  FROM appointment_all WHERE status <> 'Cancelled'
  GROUP BY appt_date;

CREATE VIEW rpt_monthly_revenue AS
  SELECT DATE_FORMAT(appt_date, '%Y-%m') AS month, SUM(total) AS revenue
  FROM appointment_all WHERE status <> 'Cancelled'
  GROUP BY DATE_FORMAT(appt_date, '%Y-%m');

CREATE VIEW rpt_branch_revenue AS
  SELECT b.branch_name AS branch, COALESCE(SUM(a.total), 0) AS revenue
  FROM branch b
  LEFT JOIN appointment_all a ON a.branch_id = b.branch_id AND a.status <> 'Cancelled'
  GROUP BY b.branch_name;

-- Customer-friendly views (customers get these, not the raw tables)
CREATE VIEW v_service_menu AS
  SELECT service_id, name, category, price, duration FROM service WHERE active = 1;

CREATE VIEW v_cart AS
  SELECT c.customer_id, s.service_id, s.name, s.price, s.duration
  FROM cart_item c JOIN service s ON s.service_id = c.service_id;

CREATE VIEW v_appointment_history AS
  SELECT a.appt_id, a.customer_id, b.branch_name AS branch, st.name AS stylist,
         a.appt_date, a.slot, a.status, a.total, p.pay_status,
         (SELECT GROUP_CONCAT(sv.name ORDER BY sv.name SEPARATOR ', ')
            FROM appointment_item i JOIN service sv ON sv.service_id = i.service_id
           WHERE i.appt_id = a.appt_id) AS services
  FROM appointment_all a
  JOIN branch b   ON b.branch_id = a.branch_id
  JOIN stylist st ON st.stylist_id = a.stylist_id
  LEFT JOIN payment p ON p.appt_id = a.appt_id;
