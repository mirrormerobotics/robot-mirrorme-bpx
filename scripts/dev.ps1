[CmdletBinding()]
param(
    [ValidateSet('unit', 'full')][string]$Mode = 'unit',
    [string]$Distribution = 'Ubuntu-20.04',
    [string]$ProxyUrl = '',
    [string]$RobonixSource = '',
    [string]$CacheRoot = '',
    [switch]$Help
)
$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Output 'Usage: .\scripts\dev.ps1 [-Mode unit|full] [-Distribution NAME] [-ProxyUrl URL] [-RobonixSource LINUX_PATH] [-CacheRoot LINUX_PATH]'
    Write-Output 'Runs offline tests in WSL. No SDK, robot connection, or hardware motion request.'
    exit 0
}
$robotRoot = Split-Path $PSScriptRoot -Parent
$linuxRoot = & wsl.exe -d $Distribution --exec wslpath -a -u $robotRoot.Replace('\', '/')
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve the repository in WSL.' }
$linuxRoot = ([string]$linuxRoot).Trim()
$arguments = @('-d', $Distribution, '--cd', $linuxRoot, '--exec', 'env')
if ($ProxyUrl) {
    $arguments += @("HTTP_PROXY=$ProxyUrl", "HTTPS_PROXY=$ProxyUrl")
}
$arguments += @('python3', 'scripts/verify_offline.py', '--mode', $Mode)
if ($RobonixSource) { $arguments += @('--robonix-source', $RobonixSource) }
if ($CacheRoot) { $arguments += @('--cache-root', $CacheRoot) }
& wsl.exe @arguments
exit $LASTEXITCODE
