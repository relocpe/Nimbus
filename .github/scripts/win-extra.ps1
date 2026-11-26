param([Parameter(Mandatory)][string]$ExePath, [string]$Out = "out")
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
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $Out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}
$start = Get-Date

# 1) Defender with real-time protection on
Say "--- Defender"
try { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop } catch { Say "cannot enable realtime: $_" }
Start-Sleep 3
$st = Get-MpComputerStatus
Say "RealTime=$($st.RealTimeProtectionEnabled) Tamper=$($st.IsTamperProtected) sigs=$($st.AntivirusSignatureVersion) age=$($st.AntivirusSignatureAge)d"

# fresh copy so real-time scanning sees it, with Mark of the Web like a browser download
$dl = Join-Path $env:USERPROFILE "Downloads"; New-Item -ItemType Directory -Force $dl | Out-Null
$copy = Join-Path $dl (Split-Path $ExePath -Leaf)
Copy-Item $ExePath $copy -Force
Set-Content -Path $copy -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3`r`nReferrerUrl=https://github.com/relocpe/Nimbus/releases`r`nHostUrl=https://github.com/"
Say "Zone.Identifier: $((Get-Content $copy -Stream Zone.Identifier) -join ' | ')"
Say "custom scan of the exe"
Start-MpScan -ScanType CustomScan -ScanPath $copy
Say "scan done; detections: $((Get-MpThreatDetection | Measure-Object).Count)"
Get-MpThreatDetection | ForEach-Object { Say "DETECTION id=$($_.ThreatID) res=$($_.Resources -join ';')" }
Get-MpThreat | ForEach-Object { Say "THREAT $($_.ThreatName)" }

# 2) launch via ShellExecute (like Explorer) with MOTW
Say "--- launch via ShellExecute with MOTW"
$p = Start-Process -FilePath $copy -PassThru
Start-Sleep 12
$p.Refresh()
Say "alive=$(-not $p.HasExited) exit=$(if ($p.HasExited) { $p.ExitCode })"
Shot "motw-launch"
Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { Say "window: $($_.ProcessName) '$($_.MainWindowTitle)'" }

# 3) scan extracted engine files with real-time on
Say "--- engine files after run"
Stop-Process -Name Nimbus* -Force -ErrorAction SilentlyContinue
Start-Sleep 2
$self = Start-Process -FilePath $copy -ArgumentList '--self-test', "$PWD\$Out\self-test.txt" -Wait -PassThru
Say "self-test exit=$($self.ExitCode)"
Get-ChildItem C:\ProgramData\Nimbus\bin -ErrorAction SilentlyContinue | ForEach-Object { Say ("  {0} {1}" -f $_.Name, $_.Length) }
Start-MpScan -ScanType CustomScan -ScanPath C:\ProgramData\Nimbus
Start-Sleep 3
Say "detections after engine scan: $((Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -ge $start } | Measure-Object).Count)"
Get-MpThreatDetection | ForEach-Object { Say "DETECTION id=$($_.ThreatID) res=$($_.Resources -join ';')" }
Get-MpThreat | ForEach-Object { Say "THREAT $($_.ThreatName)" }
try {
  Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; StartTime = $start } -ErrorAction Stop |
    Where-Object { $_.Id -in 1006,1007,1008,1116,1117,1118,1119,5007 } | ForEach-Object { Say ("DEF id={0}: {1}" -f $_.Id, (($_.Message -replace "\s+", " ").Substring(0, [Math]::Min(300, $_.Message.Length)))) }
} catch { Say "no defender events" }
Get-ChildItem C:\ProgramData\Nimbus\*.log -ErrorAction SilentlyContinue | ForEach-Object { Say "--- $($_.Name)"; Get-Content $_ | Select-Object -Last 30 | ForEach-Object { Say "  $_" } }
Say "=== done"
