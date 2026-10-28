# Concurrency demo: locking, a lock wait, a double-booking race and a DEADLOCK.
# It opens TWO MySQL sessions (A and B) at the same time.
# Called by run.ps1 (which sets $env:MYSQL_PWD, $Port and $Mysql), or run it alone.
param(
  [int]$Port = 3305,
  [string]$Mysql = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe',
  [string]$OutDir = (Join-Path $PSScriptRoot '..\output')
)
$ErrorActionPreference = 'Continue'
$tmp = Join-Path $env:TEMP 'salon_conc'
New-Item -ItemType Directory -Force $tmp | Out-Null
$common = @('-u','root','-h','127.0.0.1','-P',$Port,'--table','--force','--verbose')

function Start-Session($name, $sql) {
  $f = Join-Path $tmp "$name.sql"; Set-Content -Path $f -Value $sql -Encoding ASCII
  $o = Join-Path $tmp "$name.out"; $e = Join-Path $tmp "$name.err"
  $p = Start-Process -FilePath $Mysql -ArgumentList ($common + @('stylist_salon')) `
       -RedirectStandardInput $f -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -PassThru
  return @{ P = $p; Out = $o; Err = $e; Name = $name }
}
function Show($s) {
  "----- $($s.Name) -----"
  Get-Content $s.Out
  Get-Content $s.Err | Where-Object { $_ -notmatch 'Using a password' }
}

$report = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------
# DEMO C1: LOCKING. A holds a row lock for ~4 s. B asks for the same row and WAITS.
# ---------------------------------------------------------------
$a = Start-Session 'C1_sessionA' @"
SELECT 'A: START TRANSACTION, locking service 1' AS step, NOW(3) AS at_time;
START TRANSACTION;
UPDATE service SET price = price WHERE service_id = 1;
SELECT SLEEP(4);
SELECT 'A: COMMIT (lock released)' AS step, NOW(3) AS at_time;
COMMIT;
"@
Start-Sleep -Milliseconds 1200
$b = Start-Session 'C1_sessionB' @"
SELECT 'B: asks for the same row (it must wait)' AS step, NOW(3) AS at_time;
START TRANSACTION;
UPDATE service SET price = price WHERE service_id = 1;
SELECT 'B: got the lock only after A committed' AS step, NOW(3) AS at_time;
COMMIT;
"@
$a.P.WaitForExit(); $b.P.WaitForExit()
[void]$report.Add('=== DEMO C1: ROW LOCKING (B waits for A) ==='); [void]$report.Add((Show $a)); [void]$report.Add((Show $b))

# ---------------------------------------------------------------
# DEMO C2: DOUBLE-BOOKING RACE. A inserts a booking but has not committed yet.
# B tries to book the same stylist/date/slot with checkout(): B waits, then A commits,
# then B is rolled back because the slot is taken.
# ---------------------------------------------------------------
$cleanup = Start-Session 'C2_prepare' @"
DELETE FROM cart_item WHERE customer_id IN (2,3);
CALL add_to_cart(3, 1, @m);
"@
$cleanup.P.WaitForExit()
$a = Start-Session 'C2_sessionA' @"
SELECT 'A: books Aman, tomorrow 17:00 (not committed yet)' AS step, NOW(3) AS at_time;
START TRANSACTION;
INSERT INTO appt_seq VALUES (NULL);
INSERT INTO appointment_downtown (appt_id, customer_id, stylist_id, appt_date, slot, total)
VALUES (LAST_INSERT_ID(), 2, 1, DATE_ADD(CURDATE(), INTERVAL 6 DAY), '17:00', 300);
SELECT SLEEP(4);
SELECT 'A: COMMIT' AS step, NOW(3) AS at_time;
COMMIT;
"@
Start-Sleep -Milliseconds 1200
$b = Start-Session 'C2_sessionB' @"
SELECT 'B: tries the SAME stylist, date and slot (waits for A)' AS step, NOW(3) AS at_time;
CALL checkout(3, 1, 1, DATE_ADD(CURDATE(), INTERVAL 6 DAY), '17:00', @m);
SELECT @m AS B_result, NOW(3) AS at_time;
"@
$a.P.WaitForExit(); $b.P.WaitForExit()
[void]$report.Add('=== DEMO C2: DOUBLE-BOOKING RACE (one wins, one is rolled back) ==='); [void]$report.Add((Show $a)); [void]$report.Add((Show $b))
$clean = Start-Session 'C2_cleanup' @"
UPDATE appointment_downtown SET status = 'Cancelled' WHERE appt_date = DATE_ADD(CURDATE(), INTERVAL 6 DAY) AND slot = '17:00';
DELETE FROM cart_item WHERE customer_id = 3;
"@
$clean.P.WaitForExit()

# ---------------------------------------------------------------
# DEMO C3: DEADLOCK. A locks service 2 then wants 3. B locks service 3 then wants 2.
# Each waits for the other forever, so MySQL picks one as the VICTIM and rolls it back
# (ERROR 1213). The other one finishes. Fix in real life: always lock in the same order.
# ---------------------------------------------------------------
$a = Start-Session 'C3_sessionA' @"
SELECT 'A: locks service 2' AS step, NOW(3) AS at_time;
START TRANSACTION;
UPDATE service SET price = price WHERE service_id = 2;
SELECT SLEEP(3);
SELECT 'A: now wants service 3 (B holds it)' AS step, NOW(3) AS at_time;
UPDATE service SET price = price WHERE service_id = 3;
SELECT 'A: next statement ran (A was not the victim)' AS step;
COMMIT;
"@
Start-Sleep -Milliseconds 1000
$b = Start-Session 'C3_sessionB' @"
SELECT 'B: locks service 3' AS step, NOW(3) AS at_time;
START TRANSACTION;
UPDATE service SET price = price WHERE service_id = 3;
SELECT SLEEP(3);
SELECT 'B: now wants service 2 (A holds it)' AS step, NOW(3) AS at_time;
UPDATE service SET price = price WHERE service_id = 2;
SELECT 'B: this line only prints because of --force; B was already rolled back by the deadlock' AS step;
COMMIT;
"@
$a.P.WaitForExit(); $b.P.WaitForExit()
[void]$report.Add('=== DEMO C3: DEADLOCK (one session is chosen as victim and rolled back) ==='); [void]$report.Add((Show $a)); [void]$report.Add((Show $b))

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$outFile = Join-Path $OutDir 'concurrency_output.txt'
$report | ForEach-Object { $_ } | Out-File -FilePath $outFile -Encoding utf8
$report | ForEach-Object { $_ }
Write-Host "`nSaved to $outFile" -ForegroundColor Green
