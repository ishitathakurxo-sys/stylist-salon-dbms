# Stylist Salon (DDBMS mini project, MySQL 8.0)

**MySQL login on this laptop:** user `root`, your own root password, host `127.0.0.1`, port **3305** (not 3306).

## Run everything
```
cd C:\Users\DELL\Documents\StylistSalon
.\run.ps1          # type your root password when asked
```
Results are saved in `output\` (screenshot them for the report).

## Or use MySQL Workbench
New connection: host 127.0.0.1, port 3305, user root, your root password. Then open and run, in order:
`database\01_schema.sql`, `02_procedures.sql`, `03_data.sql`, `04_demo.sql`, `05_security_roles.sql`, `06_middleware_demo.sql`.

## Folders
- `database\`  all SQL (+ `07_concurrency_demo.ps1` for lock / race / deadlock)
- `docs\REPORT.md`  the project write-up (DBLC, ER, 3NF, fragmentation, WAL, middleware case study, security, viva)
- `website\index.html`  front end (simulated in the browser)
- `output\`  saved demo results

Demo logins in the database: riya@mail.com / pass123 (customer), admin@salon.com / admin123, aman@salon.com / style123.
MySQL users: u_customer / Cust@1234, u_stylist / Style@1234, u_admin / Admin@1234.

