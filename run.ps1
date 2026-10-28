# Builds the Stylist Salon database in MySQL and runs every demo.
# Usage (PowerShell, inside this folder):   .\run.ps1
# It asks for your MySQL root password once. Output is saved in the "output" folder.
param([int]$Port = 3305)

$Mysql = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe'
$Db    = Join-Path $PSScriptRoot 'database'
$Out   = Join-Path $PSScriptRoot 'output'
New-Item -ItemType Directory -Force $Out | Out-Null

if (-not $env:MYSQL_PWD) {
  $sec = Read-Host 'MySQL root password' -AsSecureString
  $env:MYSQL_PWD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$base = @('-u','root','-h','127.0.0.1','-P',$Port)

function Run-Sql($file, $extra, $outName) {
  Write-Host "Running $file ..." -ForegroundColor Cyan
  $src = Join-Path $Db $file
  $o = Join-Path $Out $outName
  # --force: keep going after an error (some demos are MEANT to fail)
  Get-Content $src -Raw -Encoding UTF8 | & $Mysql @base @extra --table --force --verbose 2>&1 |
    Where-Object { $_ -notmatch 'Using a password on the command line' } | Out-File $o -Encoding utf8
}

# 1-3: build (no pretty output needed, but errors are shown)
foreach ($f in '01_schema.sql','02_procedures.sql','03_data.sql') {
  Write-Host "Running $f ..." -ForegroundColor Cyan
  $r = Get-Content (Join-Path $Db $f) -Raw -Encoding UTF8 | & $Mysql @base 2>&1 | Where-Object { $_ -notmatch 'Using a password' }
  if ($r) { Write-Host $r -ForegroundColor Red; Write-Host "Stopped: fix the error above." -ForegroundColor Red; exit 1 }
}
Run-Sql '04_demo.sql'          @('stylist_salon') 'demo_output.txt'
Run-Sql '05_security_roles.sql' @('stylist_salon') 'security_setup_output.txt'

# security tests: log in as the real limited users
Write-Host "Running security tests as u_customer and u_stylist ..." -ForegroundColor Cyan
$saved = $env:MYSQL_PWD
$env:MYSQL_PWD = 'Cust@1234'
Get-Content (Join-Path $Db '05b_security_test_customer.sql') -Raw | & $Mysql -u u_customer -h 127.0.0.1 -P $Port --table --force --verbose 2>&1 |
  Where-Object { $_ -notmatch 'Using a password' } | Out-File (Join-Path $Out 'security_test_customer.txt') -Encoding utf8
$env:MYSQL_PWD = 'Style@1234'
Get-Content (Join-Path $Db '05c_security_test_stylist.sql') -Raw | & $Mysql -u u_stylist -h 127.0.0.1 -P $Port --table --force --verbose 2>&1 |
  Where-Object { $_ -notmatch 'Using a password' } | Out-File (Join-Path $Out 'security_test_stylist.txt') -Encoding utf8
$env:MYSQL_PWD = $saved

Run-Sql '06_middleware_demo.sql' @('stylist_salon') 'middleware_output.txt'

Write-Host "Running concurrency demo (about 30 seconds) ..." -ForegroundColor Cyan
& (Join-Path $Db '07_concurrency_demo.ps1') -Port $Port -Mysql $Mysql -OutDir $Out | Out-Null

Write-Host "`nDONE. Open the 'output' folder for the results (screenshot them for your report)." -ForegroundColor Green
Get-ChildItem $Out | Select-Object Name, Length
