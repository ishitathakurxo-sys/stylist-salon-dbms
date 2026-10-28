import re, html, os, subprocess, sys, json
ROOT = 'C:/Users/DELL/Documents/StylistSalon'
TPL = 'C:/Users/DELL/AppData/Local/Temp/claude/C--Users-DELL/be8211b9-da43-47c8-bd7b-abf71dc5303a/scratchpad/tpl'
SHOT = ROOT + '/screenshots'
EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
OUTDIR = ROOT + '/report'; os.makedirs(OUTDIR, exist_ok=True)

# ---- details printed on the cover (edit these and re-run build_report.py, or edit the HTML) ----
NAME, UID, CLASS, SECTION, TEACHER, TEACHER_ROLE = 'ISHITA THAKUR', '26MCI10169', 'MAM-3', 'B', 'Mr. Chanchal Sharma', ''
SEMESTER, SUBJECT, SUBCODE, DATE = 'I', 'PL/SQL', '26CAP-602', '28-10-2026'
TITLE = 'Stylist Salon: Online Appointment Booking System'
SUBTITLE = '(Distributed Database Management System mini project, MySQL)'
GITHUB = 'Not uploaded (full source code is in the project folder: database/, website/, docs/).'

E = html.escape
def rd(p): return open(p, encoding='utf-8').read()
def grab(path, start, end=None, include_end=False):
    t = rd(path); m = re.search(start, t, re.S | re.M)
    if not m: return '(not found: %s)' % start
    s = m.start()
    if end is None: return t[s:].rstrip()
    m2 = re.search(end, t[m.end():], re.S | re.M)
    e = m.end() + (m2.end() if include_end else m2.start()) if m2 else len(t)
    return t[s:e].rstrip()
def code(txt): return '<pre class="code">%s</pre>' % E(txt)
FIG = [0]
def img(path, cap, cls=''):
    FIG[0] += 1
    cap = 'Fig %d. ' % FIG[0] + re.sub(r'^Fig \d+\. ', '', cap)
    return '<figure class="%s"><img src="file:///%s"><figcaption>%s</figcaption></figure>' % (cls, path, E(cap))

D = ROOT + '/database/'
schema_frag = grab(D+'01_schema.sql', r'CREATE TABLE appointment_downtown', r'\);\n', True)
schema_cust = grab(D+'01_schema.sql', r'CREATE TABLE customer', r'\);\n', True)
schema_view = grab(D+'01_schema.sql', r'CREATE VIEW appointment_all', r';\n', True)
trig = grab(D+'01_schema.sql', r'CREATE TRIGGER trg_bi_downtown', r'CREATE TRIGGER trg_bu_downtown') + '\n' + \
       grab(D+'01_schema.sql', r'CREATE TRIGGER trg_au_downtown', r'END\$\$', True)
reg = grab(D+'02_procedures.sql', r'CREATE PROCEDURE register_customer', r'-- Login') + '\n' + \
      grab(D+'02_procedures.sql', r'CREATE FUNCTION login_customer', r'END\$\$', True)
checkout = grab(D+'02_procedures.sql', r'-- CHECKOUT = ONE TRANSACTION', r'-- =====+\n-- FEATURE 4')
report_rev = grab(D+'02_procedures.sql', r'-- A global question', r'DELIMITER ;')
roles = grab(D+'05_security_roles.sql', r'CREATE ROLE', r'-- Login accounts')
site_js = grab(ROOT+'/website/index.html', r'function book\(\)\{', r'function cancel')

def S(name): return SHOT + '/report_chunks/' + name + '.png'
def W(name): return SHOT + '/website/' + name + '.png'

def F(name): return SHOT + '/report_final/' + name + '.png'

# ---- short code excerpts (main parts only) ----
CODE_FRAG = """-- Horizontal fragment: one table per branch (same shape for Campus and Mall)
CREATE TABLE appointment_downtown (
  appt_id INT PRIMARY KEY, customer_id INT NOT NULL, stylist_id INT NOT NULL,
  appt_date DATE NOT NULL, slot CHAR(5) NOT NULL,
  status ENUM('Booked','In Progress','Completed','Cancelled') NOT NULL DEFAULT 'Booked',
  total DECIMAL(8,2) NOT NULL,
  -- "stylist|date|slot" while alive, NULL when cancelled -> UNIQUE = no double booking
  active_key VARCHAR(40) GENERATED ALWAYS AS
    (IF(status='Cancelled', NULL, CONCAT(stylist_id,'|',appt_date,'|',slot))) STORED,
  UNIQUE KEY ux_slot (active_key), ... FOREIGN KEYs ...);

-- Global view: the 3 fragments look like ONE table
CREATE VIEW appointment_all AS
  SELECT 1 AS branch_id, appt_id, customer_id, stylist_id, appt_date, slot, status, total FROM appointment_downtown
  UNION ALL SELECT 2, appt_id, customer_id, stylist_id, appt_date, slot, status, total FROM appointment_campus
  UNION ALL SELECT 3, appt_id, customer_id, stylist_id, appt_date, slot, status, total FROM appointment_mall;"""

CODE_TRIG = """CREATE TRIGGER trg_bi_downtown BEFORE INSERT ON appointment_downtown FOR EACH ROW
BEGIN
  IF NEW.appt_date < CURDATE() AND @seed_mode IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot book a past date';
  END IF;
  IF (SELECT branch_id FROM stylist WHERE stylist_id = NEW.stylist_id) <> 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fragment rule: stylist not in Downtown';
  END IF;
END;
CREATE TRIGGER trg_au_downtown AFTER UPDATE ON appointment_downtown FOR EACH ROW
BEGIN
  IF NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled' THEN
    INSERT INTO cancel_log (appt_id, cancelled_on, branch_name) VALUES (OLD.appt_id, NOW(), 'Downtown');
  END IF;
END;"""

CODE_CHECKOUT = """CREATE PROCEDURE checkout(IN p_customer INT, IN p_branch INT, IN p_stylist INT,
                          IN p_date DATE, IN p_slot CHAR(5), OUT p_msg VARCHAR(200))
BEGIN
  ... DECLARE variables ...
  DECLARE EXIT HANDLER FOR 1062            -- UNIQUE slot key hit = slot already taken
  BEGIN ROLLBACK; SET p_msg = 'ROLLBACK: that stylist is already booked ...'; END;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION    -- any other error (past date, wrong branch ...)
  BEGIN GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT; ROLLBACK;
        SET p_msg = CONCAT('ROLLBACK: ', v_err, '. Nothing saved.'); END;

  START TRANSACTION;
  ... checks: cart not empty, date not in the past,
      stylist works at this branch and does every service in the cart ...
  INSERT INTO appt_seq VALUES (NULL);  SET v_id = LAST_INSERT_ID();
  IF p_branch = 1 THEN INSERT INTO appointment_downtown (...) VALUES (...);   -- right fragment
  ELSEIF p_branch = 2 THEN INSERT INTO appointment_campus (...) VALUES (...);
  ELSEIF p_branch = 3 THEN INSERT INTO appointment_mall (...) VALUES (...);  END IF;
  INSERT INTO appointment_item SELECT v_id, service_id, price FROM v_cart WHERE customer_id = p_customer;
  INSERT INTO payment (appt_id, amount) VALUES (v_id, v_total);
  DELETE FROM cart_item WHERE customer_id = p_customer;
  COMMIT;
  SET p_msg = CONCAT('COMMIT: appointment ', v_id, ' booked ...');
END"""

CODE_LOGIN = """-- salted SHA-256 hash, the real password is never stored
INSERT INTO customer (name, phone, email, address, salt, password_hash, home_branch)
VALUES (p_name, p_phone, p_email, p_address, v_salt, SHA2(CONCAT(v_salt, p_password), 256), p_branch);

CREATE FUNCTION login_customer(p_email VARCHAR(60), p_password VARCHAR(100)) RETURNS INT READS SQL DATA
BEGIN
  DECLARE v_id INT DEFAULT 0;
  SELECT customer_id INTO v_id FROM customer
  WHERE email = p_email AND password_hash = SHA2(CONCAT(salt, p_password), 256) LIMIT 1;
  RETURN v_id;                                  -- 0 = wrong email or password
END"""

CODE_ROLES = """CREATE ROLE 'salon_customer', 'salon_stylist', 'salon_admin';
GRANT SELECT  ON stylist_salon.v_service_menu       TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.checkout   TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.cancel_appointment TO 'salon_customer';
GRANT EXECUTE ON PROCEDURE stylist_salon.set_status TO 'salon_stylist';
GRANT ALL PRIVILEGES ON stylist_salon.*             TO 'salon_admin';"""

CODE_QUERY = """-- global query split into one small query per branch, answers added (WITH ROLLUP = total row)
SELECT IF(GROUPING(site),'GLOBAL TOTAL',site) AS site, SUM(revenue) AS revenue FROM (
  SELECT 'Downtown'    AS site, COALESCE(SUM(total),0) AS revenue FROM appointment_downtown WHERE status<>'Cancelled'
  UNION ALL SELECT 'Campus Road', COALESCE(SUM(total),0) FROM appointment_campus WHERE status<>'Cancelled'
  UNION ALL SELECT 'Mall Road',   COALESCE(SUM(total),0) FROM appointment_mall   WHERE status<>'Cancelled'
) AS branch_answers GROUP BY site WITH ROLLUP;"""

CODE_JS = """function book(){            // website: simulates the checkout transaction
 ... checks login, cart, branch, stylist, date, slot ...
 log("BEGIN transaction");
 if(taken(+f.st,f.date,f.slot)){          // same stylist + date + slot already booked
   log("INSERT ... blocked: trigger fired"); log("ROLLBACK: nothing was saved");
   S.msg={k:"er",t:"That slot was just taken. The booking was rolled back."}; return draw()}
 S.appts.push({id:id,cu:S.user.name,b:f.branch,st:+f.st,d:f.date,sl:f.slot,it:S.cart.slice(),s:"Booked"});
 log("INSERT INTO payment (...)"); log("COMMIT: booking saved"); ... }"""

def fig(path, cap, cls=''):
    return img(path, cap, cls)

def build(pages):
    toc_rows = [('Introduction / Background', pages.get('intro', '')),
                ('Objectives / Technologies Used', pages.get('obj', '')),
                ('Requirements and System Design', pages.get('req', '')),
                ('Source Code & Output', pages.get('code', '')),
                ('Functionalities', pages.get('func', '')),
                ('Conclusion / Future Work / Learning Outcomes', pages.get('concl', ''))]
    toc = ''.join('<tr><td>%d</td><td>%s</td><td>%s</td></tr>' % (i+1, E(n), p) for i, (n, p) in enumerate(toc_rows))

    css = '''
@page{size:Letter;margin:1.42in .85in .85in .85in;@bottom-center{content:counter(page);font:10pt "Times New Roman"}}
@page :first{@bottom-center{content:none}}
*{box-sizing:border-box}
body{font:12pt/1.3 "Times New Roman",Times,serif;color:#000;margin:0}
h1,h2,h3{break-after:avoid;font-size:14pt;font-weight:bold;font-family:"Times New Roman",Times,serif;margin:10px 0 3px}
p{margin:3px 0;text-align:justify}ul{margin:2px 0 4px 0;padding-left:22px}li{margin:1px 0;text-align:justify}
.cover{height:7.9in;position:relative;text-align:center}
.cover .cu{height:92px;margin-top:20px}
.cover h2{font-size:14pt;margin:46px 0 4px}.cover .on{font-size:12pt;margin:4px 0}
.cover .ttl{font-size:14pt;font-weight:bold;margin:18px 0 4px}.cover .sub{font-size:12pt;margin:0}
.sub2{position:absolute;bottom:.3in;left:0;right:0;display:flex;justify-content:space-between;text-align:left;font-size:12pt}
.sub2 b{display:block;margin-bottom:4px}
.pb{break-before:page}
table.t{border-collapse:collapse;width:100%;margin:4px 0;font-size:12pt;line-height:1.2}
table.t th,table.t td{border:1px solid #444;padding:2px 6px;text-align:left;vertical-align:top}
table.t th{background:#eee}
table.toc{border-collapse:collapse;width:100%;margin-top:24px;font-size:12pt}
table.toc th,table.toc td{border:1px solid #000;padding:9px 12px}table.toc th{background:#f0f0f0}
.toctitle{font-size:14pt;font-weight:bold;text-align:center;margin-top:10px}
pre{font:8.5pt/1.2 Consolas,"Courier New",monospace;white-space:pre-wrap;word-break:break-word;margin:3px 0;padding:5px 8px;background:#f6f6f6;border:1px solid #ccc}
pre.er{font-size:9pt}
figure{margin:5px 0 8px;text-align:center;break-inside:avoid}
figure img{max-width:100%;border:1px solid #bbb}
figure.web img{width:100%;height:2.55in;object-fit:cover;object-position:top}
figcaption{font-size:11pt;font-style:italic;margin-top:2px}
.flow{display:flex;align-items:center;justify-content:center;gap:5px;flex-wrap:wrap;margin:6px 0;font-size:11pt}
.flow div.b{border:1.5px solid #333;border-radius:6px;padding:4px 7px;text-align:center;background:#fafafa}
.flow span{font-size:14pt}
.note{font-style:italic}
'''
    cover = f'''
<div class="cover">
 <img class="cu" src="file:///{TPL}/p1_Image16.png">
 <h2>Mini Project Report</h2><div class="on">On</div>
 <div class="ttl">{E(TITLE)}</div><p class="sub" style="text-align:center">{E(SUBTITLE)}</p>
 <div class="sub2">
  <div><b>SUBMITTED BY:</b>{E(NAME)}<br>UID: {E(UID)}<br>BRANCH: {E(CLASS)}<br>SECTION / GROUP: {E(SECTION)}<br>SEMESTER: {E(SEMESTER)}</div>
  <div style="text-align:left"><b>SUBMITTED TO:</b>{E(TEACHER)}<br>SUBJECT: {E(SUBJECT)}<br>SUBJECT CODE: {E(SUBCODE)}<br>DATE: {E(DATE)}</div>
 </div>
</div>'''
    index = f'''<div class="pb"></div><div class="toctitle">Table of Content</div>
<table class="toc"><tr><th>S. No.</th><th>Name</th><th>Page no.</th></tr>{toc}</table>'''

    text = '''<div class="pb"></div>
<h1 id="intro">1. Introduction</h1>
<p>This report describes <b>Stylist Salon</b>, an online appointment booking system for a salon chain with three branches: <b>Downtown, Campus Road and Mall Road</b>. Customers register, search services, fill an appointment cart and book a stylist for a date and time slot. Each booking is stored in its own branch's table, and the same stylist can never be booked twice for the same date and slot. The project is a <b>Distributed Database Management System (DDBMS)</b> mini project built in MySQL.</p>
<h1>2. Background</h1>
<p>A salon chain has three problems: many online bookings can clash, each branch mostly uses its own data, and the owner still wants one combined report. A distributed database solves this. Appointment data is split by branch (fragmentation) and kept at that branch (allocation), shared data such as the service menu is copied everywhere (replication), and a global view shows everything as one table. Here the three "sites" are three tables on one MySQL 8.0 server; the design is the same as for separate machines.</p>
<h1 id="obj">3. Objectives</h1>
<ul><li>User registration, login, profile update; admin service and staff management; search by name, category and price.</li>
<li>Appointment cart, checkout, history, status flow, cancel and reschedule; reports for services, hours, stylists and revenue.</li>
<li>Demonstrate: fragmentation, replication, data dictionary, query processing, ACID, locking, deadlock, recovery, triggers, roles and 3NF.</li></ul>
<h1>4. Technologies Used</h1>
<ul><li><b>Database:</b> MySQL 8.0.43 (InnoDB) with stored procedures, functions, triggers, views, roles and CHECK constraints; MySQL Workbench and command-line client.</li>
<li><b>Front end:</b> HTML5, CSS3 and JavaScript single page that simulates the database logic in the browser.</li>
<li><b>Automation:</b> PowerShell scripts that build the database and run every demo, including two simultaneous sessions for locking tests.</li></ul>
<h1 id="req">5. Requirements</h1>
<ul><li>MySQL Server 8.0.16 or later (CHECK constraints) and MySQL Workbench or the command-line client.</li>
<li>PowerShell (to run <i>run.ps1</i>) and a modern web browser for <i>website/index.html</i>.</li></ul>

<h1>6. System Design</h1>
<h2>Architecture Overview</h2>
<p>Every action in the web page becomes a call to a stored procedure. The procedure checks the rules, saves data inside a transaction, and writes to the correct branch table. Reports read the global view.</p>
<div class="flow"><div class="b">Customer / Admin<br>(web page)</div><span>&rarr;</span><div class="b">Stored<br>procedures</div><span>&rarr;</span><div class="b">Triggers and<br>constraints</div><span>&rarr;</span><div class="b">Branch tables<br>Downtown | Campus | Mall</div><span>&rarr;</span><div class="b">Global view<br>appointment_all</div><span>&rarr;</span><div class="b">Reports</div></div>
<h2>Database Life Cycle (DBLC)</h2>
<table class="t"><tr><th style="width:30%">Phase</th><th>What was done</th></tr>
<tr><td>Requirements</td><td>Six features: users, services and staff, cart, appointments, reports, security.</td></tr>
<tr><td>Conceptual / logical</td><td>ER diagram, then tables normalized to 3NF.</td></tr>
<tr><td>Distributed design</td><td>Fragments per branch, allocation, replicated menu, data dictionary.</td></tr>
<tr><td>Physical / implementation</td><td>InnoDB tables, keys, UNIQUE slot index; schema, triggers, procedures, data (files 01 to 03).</td></tr>
<tr><td>Testing / maintenance</td><td>Good and bad test cases (file 04), concurrency tests, roles and users (file 05).</td></tr></table>
<h2>ER Diagram and Normalization (3NF)</h2>
<pre class="er">BRANCH 1 ----&lt; STYLIST &gt;----&lt; STYLIST_SERVICE &gt;---- SERVICE
   |              |                                    |
   +--&lt; CUSTOMER  +---&lt; APPOINTMENT &gt;---&lt; APPOINTMENT_ITEM &gt;-+     APPOINTMENT 1 ---- 1 PAYMENT
          +--&lt; CART_ITEM &gt;--- SERVICE</pre>
<ul><li><b>1NF:</b> repeating groups (service 1, service 2) moved to rows of <i>appointment_item</i>.</li>
<li><b>2NF:</b> service name and category depend only on <i>service_id</i>, so they live in <i>service</i>.</li>
<li><b>3NF:</b> customer, branch and stylist facts are stored once each in their own table. The price is copied into <i>appointment_item</i> on purpose, to keep the price paid at booking time.</li></ul>
<p><b>Tables:</b> branch, time_slot, service, stylist, stylist_service, customer (salted hash, role), cart_item, appointment_downtown / _campus / _mall, appointment_item, payment, cancel_log, service_replica, data_dictionary.</p>
<h2>Distributed Database Design</h2>
<p><b>Horizontal fragmentation:</b> the appointment table is cut by rows into one fragment per branch. A trigger enforces the rule so a row cannot enter the wrong fragment.</p>
<table class="t"><tr><th>Fragment</th><th>Rule</th><th>Allocation (stored at)</th></tr>
<tr><td>appointment_downtown</td><td>stylist.branch_id = 1</td><td>Downtown site</td></tr>
<tr><td>appointment_campus</td><td>stylist.branch_id = 2</td><td>Campus Road site</td></tr>
<tr><td>appointment_mall</td><td>stylist.branch_id = 3</td><td>Mall Road site</td></tr></table>
<p><b>Replication:</b> service, branch and time_slot are copied to every site; <i>service_replica</i> holds one copy per site and triggers keep the copies equal to the master. <b>Data dictionary:</b> table <i>data_dictionary</i> lists each table, its fragment type, rule and site. <b>Transparency:</b> the view <i>appointment_all</i> (UNION ALL) hides the split. Type: homogeneous DDBMS (all sites MySQL).</p>
<h2>Query Processing</h2>
<p>A global question such as "total revenue of all branches" is split into one small query per branch (each runs at one site) and the answers are added (Fig. 3). A question about one branch reads only that fragment.</p>
<h2>Transactions, ACID, Locking, Deadlock and Recovery</h2>
<p>Checkout is one transaction: appointment, services, payment, empty cart. Any error means ROLLBACK and nothing is saved; success means COMMIT.</p>
<table class="t"><tr><td style="width:19%"><b>Atomicity</b></td><td>checkout rolls back on any error; ROLLBACK and SAVEPOINT demo</td></tr>
<tr><td><b>Consistency</b></td><td>CHECK, FOREIGN KEY, UNIQUE and trigger rules refuse bad data</td></tr>
<tr><td><b>Isolation</b></td><td>InnoDB row locks: a second session waits; two users cannot take one slot</td></tr>
<tr><td><b>Durability</b></td><td>redo log flushed at every COMMIT (write-ahead logging)</td></tr></table>
<p><b>No double booking:</b> <i>active_key</i> (stylist|date|slot) is UNIQUE; cancelling sets it to NULL, which frees the slot. <b>Deadlock:</b> A holds service 2 and wants 3, B holds 3 and wants 2; MySQL detects the cycle and rolls one session back (ERROR 1213). Prevention: lock in the same order, keep transactions short.</p>
<p><b>Write-Ahead Logging (WAL):</b> the log record is written to disk before the data page. After a crash, committed work is replayed from the log (REDO) and unfinished work is undone (UNDO). In the demo the log counter <i>Innodb_os_log_written</i> rose from 955392 to 957440 bytes after one COMMIT, with <i>innodb_flush_log_at_trx_commit = 1</i>.</p>
<h2>Triggers and Security</h2>
<ul><li><b>Triggers:</b> before insert (block past dates, block a stylist of another branch), before update (no rescheduling into the past), after update (write <i>cancel_log</i> when cancelled), and two on <i>service</i> that copy changes to every site.</li>
<li><b>Passwords:</b> SHA-256 of (random salt + password); the real password is never stored.</li>
<li><b>Bind variables:</b> every procedure uses parameters, no SQL is built from user text, so injection fails (<i>x' OR '1'='1</i> returns 0).</li>
<li><b>Roles:</b> <i>salon_customer</i> (menu, cart, book, cancel, reschedule), <i>salon_stylist</i> (view appointments, change status), <i>salon_admin</i> (everything). Only admin touches tables directly; others get EXECUTE on specific procedures (Fig. 5).</li></ul>
<h2>Case Study: Middleware over Different Databases</h2>
<p>Downtown keeps an old system (APPT_NO, text dates like 28-OCT-2026, money in paise); Campus Road keeps a newer app (id, DATETIME, rupees). A middleware layer gives one <b>integrated view</b>:</p>
<table class="t"><tr><th style="width:22%">Middleware part</th><th>Job and salon example</th></tr>
<tr><td>Schema mapping</td><td>APPT_NO and id both become appt_ref</td></tr>
<tr><td>Query translation</td><td>one global query rewritten per source: APPT_DT = '29-OCT-2026' for Downtown, DATE(starts_at) = '2026-10-29' for Campus</td></tr>
<tr><td>Data conversion</td><td>text date to DATE, paise / 100 to rupees</td></tr>
<tr><td>Source selection</td><td>a Campus-only question never touches Downtown</td></tr>
<tr><td>Result integration</td><td>UNION ALL of the mapped views = integrated_appointments</td></tr></table>
<p>Benefit: one global view and local freedom for each branch. Cost: an extra layer, slower queries, and cross-system transactions need two-phase commit. Demo: <i>06_middleware_demo.sql</i>.</p>'''

    srccode = f'''<h1 id="code">7. Source Code &amp; Output</h1>
<p>Only the main code is shown for explanation; the full code is in <i>database/01_schema.sql</i> to <i>07_concurrency_demo.ps1</i>.</p>
<h2>Database code: fragments and global view</h2>{code(CODE_FRAG)}
<h2>Database code: triggers</h2>{code(CODE_TRIG)}
<h2>Database code: checkout transaction</h2>{code(CODE_CHECKOUT)}
<h2>Database code: query processing</h2>{code(CODE_QUERY)}
<h2>Database code: registration and login</h2>{code(CODE_LOGIN)}
<h2>Database code: roles</h2>{code(CODE_ROLES)}
<h2>Front-End code</h2>{code(CODE_JS)}
<h2>Output</h2>
{fig(W('01_customer_services'), 'Fig 1. Website: service menu with search, category and price filters', 'web')}
{fig(F('s_checkout'), 'Fig 2. Checkout: COMMIT for a free slot, ROLLBACK for a clash, past date and wrong branch')}
{fig(F('s_query'), 'Fig 3. Query processing: branch answers, then the global total')}
{fig(F('s_fragments'), 'Fig 4. Fragmentation: rows stored per branch and the data dictionary')}
{fig(F('s_security_customer'), 'Fig 6. Security: customer role is denied direct table access')}
{fig(F('s_acid'), 'Fig 6. Write-ahead log: log is flushed at every COMMIT and the bytes written rise')}
{fig(F('s_race'), 'Fig 8. Concurrency: two users race for one slot; the second is rolled back')}
{fig(F('s_deadlock'), 'Fig 9. Deadlock: MySQL rolls one session back (ERROR 1213)')}'''

    rest = '''<h1 id="func">8. Functionalities</h1>
<ul><li><b>Users:</b> registration, login (salted hash), profile update. <b>Services and staff:</b> admin add, update, remove; search by name, category and price range; add stylists and assign services.</li>
<li><b>Cart and appointments:</b> add, update and remove services; checkout with branch, stylist, date and slot; history; Booked, In Progress, Completed, Cancelled; cancel and reschedule.</li>
<li><b>Reports:</b> most booked service, busiest hours, stylist-wise bookings, daily and monthly revenue, revenue per branch.</li>
<li><b>Distributed and security:</b> fragments, global view, replication, data dictionary, locking, deadlock handling, write-ahead log, roles and bind variables.</li></ul>
<h1 id="concl">9. Conclusion</h1>
<p>Stylist Salon is a working distributed booking database. Appointments are fragmented by branch yet read as one table, the menu is replicated, and every booking is all-or-nothing. Tests showed that double booking, past dates, wrong-branch bookings and bad data are rejected, locks and deadlocks are handled, and each role does only its own job.</p>
<h1>10. Future Work</h1>
<ul><li>Place the fragments on separate MySQL servers (FEDERATED tables or replication) with two-phase commit.</li>
<li>Connect the web page to the database through an API; add online payment and reminders.</li>
<li>Stronger hashing (bcrypt or Argon2), HTTPS and regular encrypted backups.</li></ul>
<h1>11. Learning Outcomes</h1>
<ul><li>Designing a 3NF schema and following the database life cycle.</li>
<li>Fragmentation, allocation, replication, data dictionary and global views; splitting a global query.</li>
<li>Transactions (COMMIT, ROLLBACK, SAVEPOINT), ACID, locking, deadlock and write-ahead logging.</li>
<li>Triggers, stored procedures, roles and bind variables; middleware integration of different databases.</li></ul>
<h1>12. GitHub link:</h1><p>''' + E(GITHUB) + '''</p>
<h1>13. Bibliography:</h1>
<ul><li>MySQL. (n.d.). MySQL 8.0 Reference Manual. Retrieved from https://dev.mysql.com/doc/refman/8.0/en/</li>
<li>MySQL. (n.d.). InnoDB redo log. Retrieved from https://dev.mysql.com/doc/refman/8.0/en/innodb-redo-log.html</li>
<li>Elmasri, R. and Navathe, S. B. Fundamentals of Database Systems. Pearson.</li></ul>'''

    return f'<!doctype html><html><head><meta charset="utf-8"><title>Stylist Salon Mini Project Report</title><style>{css}</style></head><body>{cover}{index}{text}{srccode}{rest}</body></html>'

def pdf(htmlfile, pdffile):
    subprocess.run([EDGE, '--headless=new', '--disable-gpu', '--no-pdf-header-footer', '--run-all-compositor-stages-before-draw',
                    '--virtual-time-budget=20000', f'--print-to-pdf={pdffile}', 'file:///' + htmlfile], capture_output=True, timeout=240)

def overlay_pdf(path):
    h = f"""<!doctype html><meta charset="utf-8"><style>@page{{size:Letter;margin:0}}html,body{{margin:0;padding:0}}
.b{{position:absolute;left:.4in;top:.4in;right:.4in;bottom:.4in;border:2px solid #000}}
.l1{{position:absolute;left:.6in;top:.55in;height:.62in}}.l2{{position:absolute;right:.6in;top:.6in;height:.5in}}
.ln{{position:absolute;left:.6in;right:.6in;top:1.3in;border-top:1px solid #777}}
</style><div class="b"></div><img class="l1" src="file:///{TPL}/p1_Image9.jpg"><img class="l2" src="file:///{TPL}/p1_Image10.png"><div class="ln"></div>"""
    f = OUTDIR + '/_overlay.html'; open(f, 'w', encoding='utf-8').write(h)
    subprocess.run([EDGE, '--headless=new', '--disable-gpu', '--no-pdf-header-footer', f'--print-to-pdf={path}', 'file:///' + f], capture_output=True, timeout=120)

def merge(raw, final):
    import pypdf
    ov = OUTDIR + '/_overlay.pdf'; overlay_pdf(ov)
    content = pypdf.PdfReader(raw); w = pypdf.PdfWriter()
    for pg in content.pages:
        base = pypdf.PdfReader(ov).pages[0]
        base.merge_page(pg)
        w.add_page(base)
    with open(final, 'wb') as fh: w.write(fh)

def find_pages(pdffile):
    import pypdf
    r = pypdf.PdfReader(pdffile); res = {}
    marks = {'intro': '1. Introduction', 'obj': '3. Objectives', 'req': '5. Requirements', 'code': '7. Source Code', 'func': '8. Functionalities', 'concl': '9. Conclusion'}
    for i, pg in enumerate(r.pages, 1):
        if i <= 2: continue
        t = pg.extract_text() or ''
        for k, m in marks.items():
            if k not in res and m in t: res[k] = i
    return res, len(r.pages)

hf = OUTDIR + '/Stylist_Salon_Project_Report.html'; pf = OUTDIR + '/Stylist_Salon_Project_Report.pdf'
pages = {}
for _ in range(2):
    FIG[0] = 0
    open(hf, 'w', encoding='utf-8').write(build(pages))
    pdf(hf, OUTDIR + '/_raw.pdf'); merge(OUTDIR + '/_raw.pdf', pf)
    pages, n = find_pages(pf)
print(pages, 'total pages', n)
