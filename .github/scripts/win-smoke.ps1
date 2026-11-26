param(
  [Parameter(Mandatory)][string]$Variant,   # full | lite | lite-noruntime
  [Parameter(Mandatory)][string]$ExePath,
  [string]$Out = "out"
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $Out | Out-Null
$log = Join-Path $Out "report.txt"
function Say($m) { $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $m; Write-Host $line; Add-Content $log $line }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Dpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
[Dpi]::SetProcessDPIAware() | Out-Null
function Shot($name) {
  try {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $Out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Say "screenshot $name ($($b.Width)x$($b.Height))"
  } catch { Say "screenshot $name failed: $_" }
}

Say "=== variant=$Variant exe=$ExePath"
$os = Get-CimInstance Win32_OperatingSystem
Say "OS: $($os.Caption) $($os.Version) build $($os.BuildNumber) arch=$($os.OSArchitecture) lang=$($os.MUILanguages -join ',')"
Say "Elevated: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))  EnableLUA=$((Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System).EnableLUA)"

# --- file facts
$fi = Get-Item $ExePath
Say "size=$($fi.Length) sha256=$((Get-FileHash $ExePath).Hash)"
$vi = $fi.VersionInfo
Say "FileVersion=$($vi.FileVersion) ProductVersion=$($vi.ProductVersion)"
$bytes = [IO.File]::ReadAllBytes($ExePath) | Select-Object -First 4096
$pe = [BitConverter]::ToInt32($bytes, 0x3C)
$machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
$optMagic = [BitConverter]::ToUInt16($bytes, $pe + 24)
$subsys = [BitConverter]::ToUInt16($bytes, $pe + 24 + 68)
Say ("PE machine=0x{0:X} (0x8664=x64) optional-magic=0x{1:X} (0x20B=PE32+) subsystem={2} (2=GUI)" -f $machine, $optMagic, $subsys)
# manifest level
$raw = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($ExePath)[0..([Math]::Min($fi.Length-1, 3000000))])
if ($raw -match 'level="(\w+)"') { Say "manifest requestedExecutionLevel=$($Matches[1])" }

# --- hide .NET for the no-runtime variant
if ($Variant -eq 'lite-noruntime') {
  Say "hiding .NET runtime"
  foreach ($d in 'C:\Program Files\dotnet', 'C:\Program Files (x86)\dotnet') { if (Test-Path $d) { Rename-Item $d ($d + '_off') -ErrorAction Continue } }
  Remove-Item 'HKLM:\SOFTWARE\dotnet' -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item 'HKLM:\SOFTWARE\WOW6432Node\dotnet' -Recurse -Force -ErrorAction SilentlyContinue
  Get-ChildItem Env: | Where-Object Name -like 'DOTNET*' | ForEach-Object { Say "env $($_.Name)=$($_.Value)"; Remove-Item "Env:$($_.Name)" }
  [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $null, 'Process')
  Say ("dotnet on PATH: " + [bool](Get-Command dotnet -ErrorAction SilentlyContinue))
}

# clean state
Remove-Item C:\ProgramData\Nimbus -Recurse -Force -ErrorAction SilentlyContinue
$start = Get-Date
Shot "00-before"

# --- normal launch
Say "launching: $ExePath"
$stdout = Join-Path $Out "stdout.txt"; $stderr = Join-Path $Out "stderr.txt"
try {
  $p = Start-Process -FilePath $ExePath -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  Say "started pid=$($p.Id)"
} catch {
  Say "START FAILED: $($_.Exception.GetType().FullName): $($_.Exception.Message) (hresult 0x$('{0:X}' -f $_.Exception.HResult))"
  $p = $null
}
if ($p) {
  foreach ($t in 3, 8, 15) {
    Start-Sleep -Seconds ($(if ($t -eq 3) { 3 } elseif ($t -eq 8) { 5 } else { 7 }))
    $p.Refresh()
    if ($p.HasExited) { Say "t+${t}s: EXITED code=$($p.ExitCode)"; break }
    Say "t+${t}s: alive, window='$($p.MainWindowTitle)' handle=$($p.MainWindowHandle) mem=$([int]($p.WorkingSet64/1MB))MB"
  }
  Shot "01-after-launch"
  Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { Say "window: $($_.ProcessName) '$($_.MainWindowTitle)'" }
  Get-Process | Where-Object { $_.ProcessName -match 'Nimbus|winws|msg|WerFault' } | ForEach-Object { Say "proc: $($_.ProcessName) pid=$($_.Id)" }
}

# --- UIA: look for tray icon / panel window
try {
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
  $root = [Windows.Automation.AutomationElement]::RootElement
  $wins = $root.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
  foreach ($w in $wins) { Say "uia top-level: '$($w.Current.Name)' class=$($w.Current.ClassName) pid=$($w.Current.ProcessId)" }
} catch { Say "uia failed: $_" }

if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force; Say "killed"; Start-Sleep 2 }
Get-Process Nimbus, winws -ErrorAction SilentlyContinue | Stop-Process -Force

foreach ($f in $stdout, $stderr) { if (Test-Path $f) { $c = Get-Content $f -Raw; Say "$(Split-Path $f -Leaf): [$c]" } }

# --- self-test and render (only meaningful when runtime is there)
if ($Variant -ne 'lite-noruntime') {
  Say "--- self-test"
  $r = Join-Path (Resolve-Path $Out) "self-test.txt"
  $sp = Start-Process -FilePath $ExePath -ArgumentList '--self-test', $r -Wait -PassThru
  Say "self-test exit=$($sp.ExitCode)"
  if (Test-Path $r) { Get-Content $r | Select-Object -First 40 | ForEach-Object { Say "  $_" } }
  Say "--- render-screens"
  $sd = Join-Path (Resolve-Path $Out) "screens"
  $rp = Start-Process -FilePath $ExePath -ArgumentList '--render-screens', $sd -Wait -PassThru
  Say "render exit=$($rp.ExitCode); files: $((Get-ChildItem $sd -ErrorAction SilentlyContinue | Measure-Object).Count)"
}

# --- files the app created
Say "--- C:\ProgramData\Nimbus"
Get-ChildItem C:\ProgramData\Nimbus -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Say ("  {0} {1}" -f $_.FullName, $_.Length) }
foreach ($f in Get-ChildItem C:\ProgramData\Nimbus\*.log -ErrorAction SilentlyContinue) {
  Say "--- $($f.Name)"; Get-Content $f | Select-Object -Last 60 | ForEach-Object { Say "  $_" }
  Copy-Item $f $Out
}
Say "--- %TEMP%\.net / extraction dirs"
Get-ChildItem "$env:TEMP\.net" -ErrorAction SilentlyContinue | ForEach-Object { Say "  $($_.FullName)" }

# --- Defender
try {
  $st = Get-MpComputerStatus
  Say "Defender: RealTime=$($st.RealTimeProtectionEnabled) AMService=$($st.AMServiceEnabled) sigs=$($st.AntivirusSignatureVersion)"
  $th = Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -ge $start.AddMinutes(-1) }
  if ($th) { $th | ForEach-Object { Say "DEFENDER DETECTION: $($_.ThreatID) resources=$($_.Resources -join ';')" } } else { Say "Defender: no detections since start" }
  Get-MpThreat | ForEach-Object { Say "threat: $($_.ThreatName)" }
} catch { Say "Defender query failed: $_" }

# --- event log
Say "--- Application event log since start"
try {
  Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $start } -ErrorAction Stop |
    Where-Object { $_.ProviderName -match '\.NET Runtime|Application Error|Application Hang|SideBySide|Windows Error Reporting|Nimbus|Defender' -or $_.LevelDisplayName -in 'Error','Warning' } |
    ForEach-Object { Say ("EVT [{0}] {1} id={2}: {3}" -f $_.LevelDisplayName, $_.ProviderName, $_.Id, ($_.Message -replace "\s+", " ")) }
} catch { Say "no matching events ($($_.Exception.Message))" }
try {
  Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; StartTime = $start } -ErrorAction Stop |
    Select-Object -First 30 | ForEach-Object { Say ("DEF id={0}: {1}" -f $_.Id, (($_.Message -replace "\s+", " ").Substring(0, [Math]::Min(250, $_.Message.Length)))) }
} catch { }
Say "=== done"
