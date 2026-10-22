[CmdletBinding()]
param(
    [ValidateSet('help','preview','start','status','stand','sit','arm','stop','clear-fault','release','forward','rotate','velocity','shutdown')]
    [string]$Action = 'help',
    [string]$RobotIp = '10.21.40.1',
    [string]$Distribution = 'Ubuntu-20.04',
    [double]$Distance = 0.1,
    [double]$Degrees = 15,
    [double]$X = 0,
    [double]$Y = 0,
    [double]$Yaw = 0,
    [double]$Duration = 10,
    [switch]$ConfirmPhysicalMotion
)
$ErrorActionPreference = 'Stop'
if ($Action -eq 'help') {
    Write-Output @'
motion-test.ps1 -Action preview|start|status|stand|sit|arm|stop|clear-fault|release|forward|rotate|velocity|shutdown
start, stand, sit and arm require -ConfirmPhysicalMotion.
Start never auto-stands or auto-arms. Each move ends disarmed; arm again explicitly.
forward: -Distance 0.1 [-Duration 10] (negative = backwards)
rotate: -Degrees 15 [-Duration 10] (negative = clockwise)
velocity: -X 0.1 -Y 0 -Yaw 0 -Duration 1 (bounded standard move RPC)
stop: disarm/cancel now. shutdown: stop deployment (does not automatically sit).
release: close SDK control session; restart provider before further SDK control.
Robot defaults to 10.21.40.1; WSL defaults to Ubuntu-20.04.
Use state-relay.ps1 first on this WSL NAT machine. See MOTION_TEST_GUIDE.md.
'@
    exit 0
}
if ($Action -in @('start','stand','sit','arm') -and -not $ConfirmPhysicalMotion) {
    throw 'This action requires -ConfirmPhysicalMotion with a local operator and physical stop available.'
}
function Invoke-WslChecked([string[]]$CommandArgs) {
    & wsl.exe -d $Distribution --exec @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
}
$container = 'rbnx_mirrorme_bpx_quadruped'
$culture = [System.Globalization.CultureInfo]::InvariantCulture
if ($Action -in @('preview','start')) {
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $linuxRoot = & wsl.exe -d $Distribution --exec wslpath -a -u $root.Replace('\','/')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve workspace path' }
    $linuxRoot = ([string]$linuxRoot).Trim()
    $userDir = & wsl.exe -d $Distribution --exec printenv HOME
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve WSL home' }
    $cache = ([string]$userDir).Trim() + '/.cache/robonix-bpx'
    $command = @('bash',"$linuxRoot/robot-mirrorme-bpx/scripts/start-sdk-read-only-docker.sh",
        '--motion-test','--confirm-physical-motion-test','--robot-ip',$RobotIp,
        '--sdk-wheel',"$linuxRoot/.deps/sdk/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl",
        '--robonix-source',"$linuxRoot/.deps/robonix",'--target-cache',"$cache/target",
        '--cargo-cache',"$cache/cargo",'--config-cache',"$cache/config",'--network-mode','host',
        '--ros-domain-id','225','--keep-manifest')
    if ($Action -eq 'preview') { $command += '--dry-run' }
    Invoke-WslChecked $command
} elseif ($Action -eq 'shutdown') {
    Invoke-WslChecked @('docker','stop','-t','30','rbnx_mirrorme_bpx_sdk')
} elseif ($Action -in @('forward','rotate','velocity')) {
    if ([double]::IsNaN($Duration) -or $Duration -le 0 -or $Duration -gt 30) { throw 'Duration must be >0 and <=30 seconds' }
    $move = @('docker','exec','-w','/pkg','-e','PYTHONPATH=/pkg:/robonix-api:/pkg/rbnx-build/codegen/proto_gen',
        $container,'python3','-m','bpx_quadruped.move_client','--duration-sec',$Duration.ToString($culture))
    if ($Action -eq 'forward') { $move += @('--forward-m',$Distance.ToString($culture)) }
    elseif ($Action -eq 'rotate') { $move += @('--rotate-deg',$Degrees.ToString($culture)) }
    else { $move += @('--linear-x',$X.ToString($culture),'--linear-y',$Y.ToString($culture),'--angular-z',$Yaw.ToString($culture)) }
    Invoke-WslChecked $move
} else {
    $localAction = $Action
    if ($Action -eq 'stop') { $localAction = 'disarm' }
    if ($Action -eq 'clear-fault') { $localAction = 'clear_fault' }
    Invoke-WslChecked @('docker','exec','-w','/pkg',$container,'python3','-m','bpx_quadruped.local_control',$localAction)
}
