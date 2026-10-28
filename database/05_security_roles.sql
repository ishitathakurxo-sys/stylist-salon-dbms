-- =====================================================================
-- STYLIST SALON (MySQL 8.0)
-- File 5 of 5: SECURITY (access control with roles)
-- Needs admin rights, so it is run as root. It is safe to run again.
--
-- Idea: nobody gets direct access to the tables. Customers and stylists
-- only get EXECUTE on the procedures they need (the procedures run with
-- the owner's rights, so the tables stay locked). Admin gets everything.
-- Demo logins (for testing only):
--   u_customer / Cust@1234     u_stylist / Style@1234     u_admin / Admin@1234
-- =====================================================================
USE stylist_salon;

DROP USER IF EXISTS 'u_customer'@'localhost', 'u_stylist'@'localhost', 'u_admin'@'localhost';
DROP ROLE IF EXISTS 'salon_customer', 'salon_stylist', 'salon_admin';

CREATE ROLE 'salon_customer', 'salon_stylist', 'salon_admin';

-- ---- CUSTOMER: browse the menu, manage own cart, book, cancel, reschedule
GRANT SELECT  ON stylist_salon.v_service_menu             TO 'salon_customer';
GRANT EXECUTE ON FUNCTION  stylist_salon.login_customer      TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.register_customer   TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.update_profile      TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.search_services     TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.add_to_cart         TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.update_cart         TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.remove_from_cart    TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.show_cart           TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.available_slots     TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.checkout            TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.my_appointments     TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.reschedule_appointment TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.cancel_appointment  TO 'salon_customer';

-- ---- STYLIST: see appointments, move them along Booked -> In Progress -> Completed
GRANT SELECT  ON stylist_salon.v_service_menu             TO 'salon_stylist';
GRANT SELECT  ON stylist_salon.v_appointment_history      TO 'salon_stylist';
GRANT SELECT  ON stylist_salon.rpt_stylist_bookings       TO 'salon_stylist';
GRANT EXECUTE ON PROCEDURE stylist_salon.search_services     TO 'salon_stylist';
GRANT EXECUTE ON PROCEDURE stylist_salon.available_slots     TO 'salon_stylist';
GRANT EXECUTE ON PROCEDURE stylist_salon.set_status          TO 'salon_stylist';

-- ---- ADMIN: everything in the salon database
GRANT ALL PRIVILEGES ON stylist_salon.* TO 'salon_admin';

-- Login accounts, each one gets exactly one role
CREATE USER 'u_customer'@'localhost' IDENTIFIED BY 'Cust@1234';
CREATE USER 'u_stylist'@'localhost'  IDENTIFIED BY 'Style@1234';
CREATE USER 'u_admin'@'localhost'    IDENTIFIED BY 'Admin@1234';
GRANT 'salon_customer' TO 'u_customer'@'localhost';
GRANT 'salon_stylist'  TO 'u_stylist'@'localhost';
GRANT 'salon_admin'    TO 'u_admin'@'localhost';
SET DEFAULT ROLE 'salon_customer' TO 'u_customer'@'localhost';
SET DEFAULT ROLE 'salon_stylist'  TO 'u_stylist'@'localhost';
SET DEFAULT ROLE 'salon_admin'    TO 'u_admin'@'localhost';

-- Show what each role may do
SHOW GRANTS FOR 'salon_customer';
SHOW GRANTS FOR 'salon_stylist';
SHOW GRANTS FOR 'salon_admin';
