-- Run as u_stylist (run.ps1 does this). Lines marked DENIED are meant to fail.
USE stylist_salon;
SELECT CURRENT_USER() AS logged_in_as, CURRENT_ROLE() AS active_role;

-- allowed
SELECT appt_id, branch, stylist, appt_date, slot, status FROM v_appointment_history WHERE status IN ('Booked','In Progress') ORDER BY appt_date;
SELECT * FROM rpt_stylist_bookings;
CALL set_status(0, 'In Progress', @m);   -- allowed to run; says "not found" because id 0 does not exist
SELECT @m AS result;

-- DENIED: a stylist cannot book, cancel, see customers, or see revenue
CALL checkout(1, 1, 1, CURDATE(), '10:00', @m);
CALL cancel_appointment(1, @m);
SELECT * FROM customer;
SELECT * FROM rpt_monthly_revenue;
DELETE FROM appointment_downtown;
