param(
  [Parameter(Mandatory)][string]$ExePath,
  [string]$Out = "out"
)
# Brings up a real split-tunnel VPN adapter (a WireGuard tunnel with a documentation-range peer) and checks
# that Nimbus sees it, pins the engine to the physical NIC and starts with that pin.
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $Out | Out-Null
$log = Join-Path $Out "report.txt"
$script:failed = 0
function Say($m) { $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $m; Write-Host $line; Add-Content $log $line }
function Check($ok, $what) { if ($ok) { Say "PASS: $what" } else { Say "FAIL: $what"; $script:failed++ } }
function Probe($name) {
  $r = Join-Path (Resolve-Path $Out) "$name.txt"
  $p = Start-Process -FilePath $ExePath -ArgumentList '--probe-network', $r -Wait -PassThru
  Say "probe $name exit=$($p.ExitCode)"
  if (Test-Path $r) { $t = Get-Content $r; $t | ForEach-Object { Say "  $_" }; return ($t -join "`n") }
  return ''
}

Remove-Item C:\ProgramData\Nimbus -Recurse -Force -ErrorAction SilentlyContinue

Say "--- before the tunnel"
$before = Probe "probe-before"
Check ($before -match 'pinned interface: none') "no VPN, no pin"
Check ($before -match 'detected: no VPN') "no VPN detected"

Say "--- installing WireGuard"
choco install wireguard -y --no-progress 2>&1 | Select-Object -Last 5 | ForEach-Object { Say "  $_" }
$wgdir = 'C:\Program Files\WireGuard'
$wg = Join-Path $wgdir 'wg.exe'; $wgui = Join-Path $wgdir 'wireguard.exe'
Check ((Test-Path $wg) -and (Test-Path $wgui)) "WireGuard installed"
if (-not (Test-Path $wgui)) { exit 1 }

$priv = (& $wg genkey).Trim()
$peerPriv = (& $wg genkey).Trim()
$peerPub = ($peerPriv | & $wg pubkey).Trim()
New-Item -ItemType Directory -Force C:\vpnsim | Out-Null
$conf = "C:\vpnsim\nimbustun.conf"
@"
[Interface]
PrivateKey = $priv
Address = 10.99.0.2/32

[Peer]
PublicKey = $peerPub
Endpoint = 203.0.113.7:51820
AllowedIPs = 10.99.0.0/24, 198.51.100.0/24
PersistentKeepalive = 5
"@ | Set-Content $conf -Encoding ascii
& $wgui /installtunnelservice $conf 2>&1 | ForEach-Object { Say "  $_" }
$up = $false
foreach ($i in 1..20) {
  Start-Sleep 1
  $a = Get-NetAdapter -Name nimbustun -ErrorAction SilentlyContinue
  if ($a -and $a.Status -eq 'Up') { $up = $true; break }
}
Get-NetAdapter | Format-Table Name, InterfaceDescription, ifIndex, Status -AutoSize | Out-String | ForEach-Object { Say $_ }
Check $up "tunnel adapter is up"
Say "routes:"; route print -4 | ForEach-Object { Say "  $_" }
$tunIdx = (Get-NetAdapter -Name nimbustun -ErrorAction SilentlyContinue).ifIndex

Say "--- with the tunnel"
$during = Probe "probe-during"
Check ($during -match 'vpn adapters: .*\b' + $tunIdx + '\b') "tunnel adapter $tunIdx detected as VPN"
Check ($during -match 'pinned interface: \d+') "engine pinned to a physical interface"
Check ($during -notmatch ('pinned interface: ' + $tunIdx + '\r?$')) "pin is not the tunnel"
Check ($during -notmatch 'detected: no VPN') "VPN reported"

Say "--- engine start with the pin"
$r = Join-Path (Resolve-Path $Out) "self-test.txt"
$sp = Start-Process -FilePath $ExePath -ArgumentList '--self-test', $r -Wait -PassThru
Say "self-test exit=$($sp.ExitCode)"
$st = if (Test-Path $r) { Get-Content $r } else { @() }
$st | ForEach-Object { Say "  $_" }
Check ($sp.ExitCode -eq 0) "self-test passes with the tunnel up"
Check (($st -join "`n") -match 'engine plan: if\d+') "engine started pinned (plan if<N>)"
foreach ($f in Get-ChildItem C:\ProgramData\Nimbus\*.log -ErrorAction SilentlyContinue) {
  Say "--- $($f.Name)"; Get-Content $f | Select-Object -Last 40 | ForEach-Object { Say "  $_" }; Copy-Item $f $Out
}

Say "--- removing the tunnel"
& $wgui /uninstalltunnelservice nimbustun 2>&1 | ForEach-Object { Say "  $_" }
Start-Sleep 4
$after = Probe "probe-after"
Check ($after -match 'pinned interface: none') "pin goes away with the tunnel"

Say "=== failures: $script:failed"
exit $script:failed
