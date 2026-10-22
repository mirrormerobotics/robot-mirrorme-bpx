[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RobotIp,
    [Parameter(Mandatory=$true)][string]$ListenIp,
    [string]$Distribution = 'Ubuntu-20.04',
    [ValidateRange(1024,65535)][int]$Port = 9873,
    [ValidateRange(1,120)][int]$Minutes = 30
)
$ErrorActionPreference = 'Stop'
$robotAddress = [System.Net.IPAddress]::Parse($RobotIp)
$listenAddress = [System.Net.IPAddress]::Parse($ListenIp)
$route = & wsl.exe -d $Distribution --exec ip -j route get $RobotIp
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve WSL address' }
$targetAddress = (($route | ConvertFrom-Json) | Select-Object -First 1).prefsrc
if (-not $targetAddress) { throw 'WSL route has no source address' }
$receiver = [System.Net.Sockets.UdpClient]::new()
$sender = [System.Net.Sockets.UdpClient]::new()
$count = 0
try {
    $receiver.Client.Bind([System.Net.IPEndPoint]::new($listenAddress,$Port))
    $receiver.Client.ReceiveTimeout = 1000
    $deadline = [DateTime]::UtcNow.AddMinutes($Minutes)
    $nextReport = [DateTime]::UtcNow.AddSeconds(10)
    $lastPacket = $null
    Write-Output "State-only UDP relay: $ListenIp`:$Port -> $targetAddress`:$Port; source $RobotIp only. Ctrl+C stops."
    while ([DateTime]::UtcNow -lt $deadline) {
        if ([DateTime]::UtcNow -ge $nextReport) {
            $remaining = [int]($deadline - [DateTime]::UtcNow).TotalSeconds
            $age = if ($null -eq $lastPacket) { 'none received' } else { '{0:F1}s' -f ([DateTime]::UtcNow-$lastPacket).TotalSeconds }
            Write-Output "Relay alive: packets=$count; last packet=$age; expires in $remaining seconds."
            if ($remaining -le 60) { Write-Warning 'Relay expires soon. Finish motion testing before it exits.' }
            $nextReport = [DateTime]::UtcNow.AddSeconds(10)
        }
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0)
        try { $bytes = $receiver.Receive([ref]$remote) }
        catch [System.Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::TimedOut) { continue }
            throw
        }
        if ($remote.Address.Equals($robotAddress)) {
            [void]$sender.Send($bytes,$bytes.Length,$targetAddress,$Port)
            $count++
            $lastPacket = [DateTime]::UtcNow
            if ($count -eq 1) { Write-Output 'First state packet received.' }
        }
    }
    Write-Warning 'Relay duration reached; state forwarding is ending. This does not confirm the robot has stopped.'
} finally {
    $receiver.Close()
    $sender.Close()
    Write-Output "Relay closed; forwarded $count packets."
}
