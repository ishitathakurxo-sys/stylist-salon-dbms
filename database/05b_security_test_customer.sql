-- Run as u_customer (run.ps1 does this). Lines marked DENIED are meant to fail.
USE stylist_salon;
SELECT CURRENT_USER() AS logged_in_as, CURRENT_ROLE() AS active_role;

-- allowed
CALL search_services('hair', NULL, NULL, NULL);
SELECT * FROM v_service_menu LIMIT 3;
SELECT login_customer('riya@mail.com', 'pass123') AS login_works;

-- DENIED: a customer cannot touch the tables or admin procedures
SELECT * FROM customer;
SELECT * FROM service;
DELETE FROM service;
UPDATE payment SET amount = 0;
CALL add_service('Free haircut', 'Hair', 1, 10, @m);
CALL report_revenue();
