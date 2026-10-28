# Stylist Salon: Online Appointment Booking System
**Distributed Database Management System (DDBMS) mini project**
Database: MySQL 8.0 (SQL + stored procedures + triggers) · Front end: `website/index.html` (demo)

---

## 1. What the project does (in simple words)

A salon has **3 branches**: Downtown, Campus Road, Mall Road. Customers book appointments online. They pick services, a stylist, a date and a time slot. The system saves the booking in **that branch's own table** and makes sure **two people can never book the same stylist at the same time**.

| Part | What it is |
|---|---|
| `database/` | The real project: tables, rules, triggers, procedures, roles, demos (MySQL) |
| `website/index.html` | The screens (register, search, cart, book, cancel, admin reports). It only *simulates* the database in the browser |
| `output/` | Saved results of every demo (use them as screenshots) |

---

## 2. Database Life Cycle (DBLC)

| Phase | What we did |
|---|---|
| 1. Requirement analysis | Listed the 6 features: users, services/staff, cart, appointments, reports, security |
| 2. Conceptual design | Found the entities (Customer, Service, Stylist, Branch, Appointment, Payment) and drew the ER diagram (section 4) |
| 3. Logical design | Turned the ER diagram into tables and normalized them to 3NF (section 5) |
| 4. Distributed design | Decided how to split and place data across 3 branches (section 6) |
| 5. Physical design | Chose MySQL/InnoDB, data types, primary/foreign keys, a UNIQUE index for slots |
| 6. Implementation | `01_schema.sql` to `03_data.sql`: tables, triggers, procedures, dummy data |
| 7. Testing | `04_demo.sql` and the concurrency demo: good cases and deliberately bad cases |
| 8. Operation and maintenance | Roles/users (`05_security_roles.sql`), reports, backup through MySQL |

---

## 3. Features and where they are in the code

| # | Feature | Procedure / object |
|---|---|---|
| 1 | Registration, login, profile update | `register_customer`, `login_customer()`, `update_profile` |
| 2 | Admin add / update / remove service | `add_service`, `update_service`, `remove_service` |
| 2 | Search by name, category, price range | `search_services` |
| 2 | Staff: add stylist, assign services | `add_stylist`, `assign_service`, `unassign_service`, `deactivate_stylist` |
| 3 | Cart: add, update, remove | `add_to_cart`, `update_cart`, `remove_from_cart`, `show_cart` |
| 3 | Checkout (stylist + date + slot) | `checkout`, `available_slots` |
| 4 | Book, history, status, cancel, reschedule | `checkout`, `my_appointments`, `set_status`, `cancel_appointment`, `reschedule_appointment` |
| 5 | Reports | views `rpt_most_booked_service`, `rpt_busiest_hours`, `rpt_stylist_bookings`, `rpt_daily_revenue`, `rpt_monthly_revenue`, procedure `report_revenue` |
| 6 | Security | roles (`05_security_roles.sql`), salted SHA-256 hashes, bind variables |

Status flow: **Booked → In Progress → Completed**. A Booked appointment can also go to **Cancelled**.

---

## 4. ER diagram

```
BRANCH 1────< STYLIST >────< STYLIST_SERVICE >────SERVICE
   │                │                                  │
   │                │                                  │
   └──< CUSTOMER    └────< APPOINTMENT >────< APPOINTMENT_ITEM >────┘
          │                     │
          └──< CART_ITEM >──────┘ (service)        APPOINTMENT 1────1 PAYMENT
```

Relationships in words:
- One **branch** has many **stylists**. One **stylist** can do many **services** and one **service** can be done by many stylists (many-to-many, table `stylist_service`).
- One **customer** has many **appointments**. One **appointment** has many **services** (table `appointment_item`) and exactly one **payment**.
- A **cart** is a list of (customer, service) pairs before booking.

---

## 5. Normalization (up to 3NF)

**Un-normalized sheet** (everything in one row):

`appointment(customer name, phone, email, branch, branch name, stylist, stylist branch, service 1, service 2, price 1, price 2, date, slot, total)`

- **1NF**: remove repeating groups (`service 1, service 2`). Every cell has one value. Services move to their own rows (`appointment_item`).
- **2NF**: remove partial dependencies. In `appointment_item`, the service name and category depend only on `service_id`, not on the whole key (`appt_id`, `service_id`), so they move to `service`.
- **3NF**: remove transitive dependencies. `customer name, phone` depend on `customer_id`, not on the appointment. `branch name` depends on `branch_id`, which depends on the stylist. So each fact lives in exactly one table: `customer`, `stylist`, `branch`, `service`.

Final tables: `branch, time_slot, service, stylist, stylist_service, customer, cart_item, appointment_downtown/campus/mall, appointment_item, payment, cancel_log`.
The price is copied into `appointment_item` **on purpose**: it records the price *at booking time*, so a later price change does not rewrite old bills.

---

## 6. Distributed database design

**Type of DDBMS:** *homogeneous* (all sites run the same DBMS, here MySQL). The case study in section 10 shows the *heterogeneous* case.

**Fragmentation (horizontal).** The `appointment` table is cut by rows, one fragment per branch:

| Fragment | Rule (predicate) | Stored at |
|---|---|---|
| `appointment_downtown` | stylist's `branch_id = 1` | Downtown site |
| `appointment_campus` | stylist's `branch_id = 2` | Campus Road site |
| `appointment_mall` | stylist's `branch_id = 3` | Mall Road site |

A trigger enforces the rule: a row cannot be inserted into the wrong fragment. The three fragments together give back the original table (**completeness**), and no row is in two fragments (**disjointness**).

**Allocation.** Each fragment is stored at its own branch. Stylists go with their branch, customers with their home branch, and payment/items go with their appointment.

**Replication.** `service`, `branch` and `time_slot` are the same everywhere, so every site can show the menu without asking another site. The table `service_replica` holds one copy per site, and triggers keep the copies in step with the master (`trg_service_ai`, `trg_service_au`).

**Data dictionary.** Table `data_dictionary` says, for every table, the fragment type, the rule and where it lives.

**Transparency.** The view `appointment_all` (`UNION ALL` of the three fragments) hides the split. A user queries one table and does not need to know about three.

> Note for the viva: the three "sites" are three tables in one MySQL server. This simulates a distributed system on one laptop. A real one would put each fragment on a different machine (for example with database links or FEDERATED tables).

---

## 7. Query processing

A **global query** such as "total revenue of all branches" is split into **one small query per branch**. Each runs at one site. The answers are then added together.

```sql
-- branch-level queries
SELECT 'Downtown', SUM(total) FROM appointment_downtown WHERE status <> 'Cancelled'
UNION ALL SELECT 'Campus Road', SUM(total) FROM appointment_campus WHERE status <> 'Cancelled'
UNION ALL SELECT 'Mall Road',   SUM(total) FROM appointment_mall   WHERE status <> 'Cancelled';
-- global answer = sum of the branch answers   (procedure report_revenue, demo 7)
```

`EXPLAIN FORMAT=TREE` on the global view shows MySQL doing exactly this: one scan per fragment, then combine.
**Optimization ideas shown:** a question about one branch reads one fragment only; the UNIQUE index finds a clashing slot without scanning; `WHERE status <> 'Cancelled'` is pushed down into each branch query.

---

## 8. Transactions: ACID, locking, concurrency, deadlock, recovery

**Booking (`checkout`) is one transaction.** Steps: save appointment → save services → save payment → empty the cart. If anything fails, **ROLLBACK**: nothing is saved and the cart is untouched. If all work, **COMMIT**.

| ACID letter | Where you see it |
|---|---|
| **A**tomicity | `checkout` rolls everything back on any error (demo 4b, 4e, 4f); `ROLLBACK` demo 9 |
| **C**onsistency | CHECK (price > 0, 10-digit phone), FOREIGN KEYs, UNIQUE slot, triggers. Bad data is refused (demo 9) |
| **I**solation | InnoDB row locks: two users cannot take the same slot (concurrency demo C1, C2) |
| **D**urability | After COMMIT the change survives a crash because of the write-ahead log (section 9) |

**No double booking.** `active_key = stylist|date|slot` is UNIQUE. Cancelled bookings set it to NULL, so the slot becomes free again.

**Locking and concurrency** (`07_concurrency_demo.ps1` opens two sessions at once):
- **C1 Row lock:** session A updates a row and has not committed. Session B wants the same row and **waits** until A commits.
- **C2 Race for a slot:** A inserts a booking but has not committed. B calls `checkout` for the same slot, **waits**, and is **rolled back** after A commits.
- **C3 Deadlock:** A locks service 2 then wants 3. B locks service 3 then wants 2. Each waits for the other. MySQL detects the cycle and **rolls back one session** (`ERROR 1213 Deadlock found`). The other one finishes. *Prevention:* always lock rows in the same order, keep transactions short.

**Recovery.** Uncommitted work is undone by `ROLLBACK`; `SAVEPOINT` undoes only part (demo 9). After a crash, InnoDB replays committed changes and undoes unfinished ones using its log.

---

## 9. Write-Ahead Logging (WAL)

**Rule:** *the log record is written to disk before the changed data page.*

Why? Writing a log record is a quick sequential write. Writing the data page can be slow and random. If the power fails:
- **Committed** transaction, page not yet written → **REDO** from the log. (Durability)
- **Uncommitted** transaction, page already written → **UNDO** it. (Atomicity)

Example with our salon, booking #14:

```
1. BEGIN  T14                         -> log: <T14 start>
2. INSERT appointment 14              -> log: <T14, appointment_downtown, row 14, new values>
3. INSERT payment 14                  -> log: <T14, payment, row 14, new values>
4. COMMIT                             -> log: <T14 commit>   ← flushed to disk NOW
5. (later) data pages written to disk, in the background
   Crash between 4 and 5?  On restart: the log says T14 committed → REDO it. Booking is not lost.
   Crash before 4?          On restart: no commit record → UNDO. Nothing half-saved.
```

**In MySQL (InnoDB)** this is the *redo log*. Demo 9 shows it:
`innodb_flush_log_at_trx_commit = 1` means the log is flushed to disk at **every COMMIT**, and `Innodb_os_log_written` (bytes written to the log) **goes up** after a COMMIT.

---

## 10. Case study: Middleware over many different databases (from the class task)

**Scenario.** Stylist Salon becomes a chain. Each branch bought its own system:
Downtown runs an **old system** (columns `APPT_NO`, `APPT_DT` as text like `28-OCT-2026`, money in paise).
Campus Road runs a **newer app** (columns `id`, `starts_at` as DATETIME, money in rupees).
The owner wants **one screen** and **one report** for all branches without rebuilding the old systems.

**Solution: a middleware layer** (the box in the notebook diagram) between the user and the sources.

```
 User / website  ──► INTEGRATED VIEW  (one common schema)
                          │
              ┌───────────┴────────────────────────────────────────┐
              │ MIDDLEWARE                                         │
              │  1. Schema mapping     APPT_NO / id  → appt_ref    │
              │  2. Query translation  global query → per-source   │
              │  3. Data conversion    text date → DATE, paise→Rs  │
              │  4. Source selection   ask only the sources needed │
              │  5. Result integration merge answers into one      │
              └───────┬─────────────────────────────┬──────────────┘
                 Downtown (old DB)            Campus Road (new DB)
```

| Middleware part | What it does | Salon example (`06_middleware_demo.sql`) |
|---|---|---|
| Schema mapping | Matches different names/structures to one common schema | `APPT_NO` and `id` both become `appt_ref`; `CUST_NAME` and `customer` become `customer` |
| Query translation | Rewrites one global query into each source's own form | "revenue on 29-Oct" becomes `WHERE APPT_DT='29-OCT-2026'` for Downtown and `WHERE DATE(starts_at)='2026-10-29'` for Campus |
| Data conversion | Converts types and units | `'28-OCT-2026'` → DATE, paise ÷ 100 → rupees, DATETIME → date + `HH:MM` |
| Source selection | Chooses which sources must be asked | A question about Campus Road never touches Downtown |
| Result integration | Merges the partial answers | `UNION ALL` of the mapped views = `integrated_appointments`; revenue parts are added |

**Result:** the user sees the **integrated view** (one table). Adding a new branch with another database only needs a new mapping, not changes to the other systems.
**Benefits:** location and heterogeneity transparency, local autonomy for each branch, one global view. **Costs:** an extra layer to maintain, slower queries (translation + merging), and cross-system transactions are hard (they need two-phase commit).

---

## 11. Active database: triggers

| Trigger | When | What it does |
|---|---|---|
| `trg_bi_downtown / campus / mall` | before insert | Blocks past dates; blocks a stylist from another branch (fragment rule) |
| `trg_bu_…` | before update | Blocks rescheduling into the past |
| `trg_au_…` | after update | If status became Cancelled → writes a row in `cancel_log` |
| `trg_service_ai / au` | after insert/update on `service` | Copies the change to every site (replication) |

---

## 12. Security

- **Hashed passwords:** `SHA2(salt + password, 256)`. A random salt is stored beside the hash, so two users with the same password get different hashes. The real password is never stored.
- **Bind variables / no SQL injection:** every procedure receives values as parameters. No SQL text is built from user input. Demo 10 shows `x' OR '1'='1` is just treated as text and login fails. A `PREPARE … ?` example is included.
- **Roles (access control):**

| Role | Can do | Cannot do |
|---|---|---|
| `salon_customer` | browse menu, cart, book, reschedule, cancel, profile | read other tables, change services, see revenue |
| `salon_stylist` | view appointments, change status | book, cancel, see customers or revenue |
| `salon_admin` | everything in the salon database | (full control) |

Nobody except admin gets direct table access. Others only get `EXECUTE` on specific procedures, which run with the owner's rights. The tests in `output/security_test_*.txt` show allowed and denied actions.

---

## 13. How to run

1. Open PowerShell in the project folder and run `.\run.ps1` (type your MySQL root password when asked). It builds everything and fills the `output` folder.
2. Or in MySQL Workbench open and run, in order: `01_schema.sql`, `02_procedures.sql`, `03_data.sql`, then `04_demo.sql`, `05_security_roles.sql`, `06_middleware_demo.sql`.
3. Open `website/index.html` in a browser for the front end.

**Demo checklist (screenshot each):** 1 users · 2 services/staff/replication · 3 cart · 4 checkout commit/rollback · 5 reschedule/status/cancel/log · 6 fragmentation + dictionary · 7 query processing · 8 reports · 9 ACID/recovery/WAL · 10 injection · security tests · middleware · concurrency (lock, race, deadlock).

---

## 14. Possible viva questions (short answers)

- **Why fragment appointments by branch?** Most queries are about one branch, so data stays near where it is used (faster, local control). The global view still gives the full picture.
- **Horizontal vs vertical fragmentation?** Horizontal splits rows; vertical splits columns. We used horizontal.
- **Why replicate the service menu?** It is read often and changed rarely, so every site reads locally.
- **What stops double booking?** The UNIQUE `active_key` (stylist|date|slot). Cancelled rows are NULL, so they free the slot.
- **What is a deadlock and how is it handled?** Two transactions wait for each other's locks. MySQL detects it and rolls one back. Prevent it by locking in a fixed order.
- **What is WAL?** Write the log before the data. It gives durability (redo) and atomicity (undo) after a crash.
- **Is this truly distributed?** It simulates distribution on one server. The design (fragments, allocation, replication, dictionary, transparency) is the same as a real one.
