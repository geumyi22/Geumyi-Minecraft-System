param(
    [Parameter(Mandatory = $true)][string]$BackupRoot,
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "day10_live_helpers.ps1")

function Day10-FourRollbackAssert {
    param([string]$Root)
    $stateFile = Join-Path $Root "four-rollback-state.json"
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { throw "Missing four-server rollback state" }
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($state.schema -ne 1 -or @($state.servers).Count -ne 3) { throw "Incomplete rollback state" }
    foreach ($entry in $state.servers) {
        $original = Join-Path $Root ("servers\" + $entry.id)
        if (-not (Test-Path -LiteralPath (Join-Path $original "server.properties") -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $original "config\paper-global.yml") -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $original "backup-manifest.json") -PathType Leaf)) {
            throw "Incomplete original server backup for $($entry.id)"
        }
        $manifest = Get-Content -LiteralPath (Join-Path $original "backup-manifest.json") -Raw | ConvertFrom-Json
        foreach ($file in @($manifest.files)) {
            $candidate = Join-Path $original ([string]$file.relative)
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
                (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ne [string]$file.sha256) {
                throw "Rollback backup checksum mismatch: $($entry.id) / $($file.relative)"
            }
        }
    }
    return $state
}

function Day10-FourStopProxies {
    param($State)

    $known = New-Object System.Collections.Generic.HashSet[int]
    foreach ($p in @($State.proxy_pids)) {
        $id = [int]$p
        if ($id -le 0) { continue }
        [void]$known.Add($id)
    }

    # Also discover only Java processes whose command line is inside the exact Day10 proxy root.
    foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction SilentlyContinue)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$proc.CommandLine) -and
            $proc.CommandLine.IndexOf([string]$State.proxy_install_root,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            [void]$known.Add([int]$proc.ProcessId)
        }
    }

    foreach ($id in @($known)) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
        if ($null -eq $proc) { continue }
        if ($proc.Name -notin @("java.exe","javaw.exe") -or
            [string]::IsNullOrWhiteSpace([string]$proc.CommandLine) -or
            $proc.CommandLine.IndexOf([string]$State.proxy_install_root,[StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue # Never touch an unrelated Java/Minecraft process.
        }
        Write-Host "Stopping Day10 proxy process PID $id..."
        Stop-Process -Id $id -Force -ErrorAction Stop
        try { Wait-Process -Id $id -Timeout 20 -ErrorAction Stop } catch { }
    }

    $deadline = (Get-Date).AddSeconds(20)
    do {
        $occupied = @()
        foreach ($port in @(25565,25566,25567)) {
            $listener = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
            foreach ($l in $listener) {
                $owner = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$l.OwningProcess) -ErrorAction SilentlyContinue
                if ($null -ne $owner -and
                    $owner.Name -in @("java.exe","javaw.exe") -and
                    -not [string]::IsNullOrWhiteSpace([string]$owner.CommandLine) -and
                    $owner.CommandLine.IndexOf([string]$State.proxy_install_root,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    Stop-Process -Id ([int]$owner.ProcessId) -Force -ErrorAction SilentlyContinue
                } else {
                    $occupied += $port
                }
            }
        }
        if ($occupied.Count -eq 0 -and
            -not (Get-NetTCPConnection -LocalPort 25565,25566,25567 -State Listen -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    foreach ($port in @(25565,25566,25567)) {
        $listener = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
        if ($listener.Count -gt 0) {
            throw "Public TCP port $port remains occupied by a non-Day10 process; rollback will not terminate it automatically"
        }
    }
}

function Day10-ReadExactly {
    param($Stream, [int]$Count)
    $buffer = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $n = $Stream.Read($buffer, $offset, $Count - $offset)
        if ($n -le 0) { throw "Unexpected EOF from RCON" }
        $offset += $n
    }
    return $buffer
}

function Day10-WriteRconPacket {
    param($Stream, [int]$Id, [int]$Type, [string]$Body)
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter($ms)
    try {
        $bw.Write([int](4 + 4 + $bodyBytes.Length + 2))
        $bw.Write([int]$Id)
        $bw.Write([int]$Type)
        $bw.Write($bodyBytes)
        $bw.Write([byte]0)
        $bw.Write([byte]0)
        $bw.Flush()
        $bytes = $ms.ToArray()
        $Stream.Write($bytes, 0, $bytes.Length)
        $Stream.Flush()
    } finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

function Day10-ReadRconPacket {
    param($Stream)
    $lenBytes = Day10-ReadExactly $Stream 4
    $length = [BitConverter]::ToInt32($lenBytes, 0)
    if ($length -lt 10 -or $length -gt 1048576) { throw "Invalid RCON packet length: $length" }
    $packet = Day10-ReadExactly $Stream $length
    $id = [BitConverter]::ToInt32($packet, 0)
    $type = [BitConverter]::ToInt32($packet, 4)
    $bodyLength = $length - 10
    $body = if ($bodyLength -gt 0) { [Text.Encoding]::UTF8.GetString($packet, 8, $bodyLength) } else { "" }
    return [pscustomobject]@{ id=$id; type=$type; body=$body }
}

function Day10-UnescapeJavaPropertyValue {
    param([string]$Value)
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $c = $Value[$i]
        if ($c -ne [char]92) {
            [void]$sb.Append($c)
            continue
        }
        if ($i + 1 -ge $Value.Length) {
            [void]$sb.Append([char]92)
            continue
        }
        $i++
        $n = $Value[$i]
        switch ($n) {
            't' { [void]$sb.Append([char]9) }
            'r' { [void]$sb.Append([char]13) }
            'n' { [void]$sb.Append([char]10) }
            'f' { [void]$sb.Append([char]12) }
            'u' {
                if ($i + 4 -ge $Value.Length) { throw "Invalid Java properties Unicode escape" }
                $hex = $Value.Substring($i + 1, 4)
                if ($hex -notmatch '^[0-9A-Fa-f]{4}$') { throw "Invalid Java properties Unicode escape" }
                [void]$sb.Append([char][Convert]::ToInt32($hex,16))
                $i += 4
            }
            default { [void]$sb.Append($n) }
        }
    }
    return $sb.ToString()
}

function Day10-ReadServerPropertyForRollback {
    param([string]$ServerDir, [string]$Key)
    $path = Join-Path $ServerDir "server.properties"
    $text = Day10-ReadUtf8Strict $path
    foreach ($line in $text.Replace((([string][char]13)+[char]10), [string][char]10).Split([char]10)) {
        $trim = $line.Trim()
        if ($trim.StartsWith("#") -or -not $trim.Contains("=")) { continue }
        $parts = $trim.Split("=", 2)
        if ($parts[0].Trim() -eq $Key) {
            return Day10-UnescapeJavaPropertyValue ($parts[1].Trim())
        }
    }
    throw "Missing server property $Key in $path"
}
function Day10-DirectRconStop {
    param([string]$ServerDir, [int]$Port)
    $password = Day10-ReadServerPropertyForRollback $ServerDir "rcon.password"
    if ([string]::IsNullOrWhiteSpace($password)) { throw "RCON password is empty" }
    $client = New-Object Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { throw "RCON connect timeout on port $Port" }
        $client.EndConnect($iar)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000
        $stream.WriteTimeout = 5000
        Day10-WriteRconPacket $stream 100 3 $password
        $authenticated = $false
        for ($i=0; $i -lt 4; $i++) {
            $p = Day10-ReadRconPacket $stream
            if ([int]$p.id -eq -1) { throw "RCON authentication failed" }
            if ([int]$p.id -eq 100 -and [int]$p.type -eq 2) { $authenticated = $true; break }
        }
        if (-not $authenticated) { throw "RCON authentication response missing" }
        Day10-WriteRconPacket $stream 101 2 "stop"
        Write-Host "Direct RCON fallback sent stop to $Port"
    } finally {
        $client.Close()
    }
}

function Day10-DisableLobbyRestartForRollback {
    $settings = Day10-Gsc "GET" "/api/settings"
    $profile = @($settings.servers | Where-Object { $_.id -eq "lobby" }) | Select-Object -First 1
    if ($null -eq $profile) { return }
    $profile.auto_start = $false
    $profile.restart_on_crash = $false
    Day10-Gsc "POST" "/api/v4/server-profile" @{action="update";server=$profile} | Out-Null
}

function Day10-StopForRollback {
    param([string]$Id, [string]$ServerDir, [int]$RconPort)
    $current = Day10-State $Id
    if ($null -eq $current -or -not [bool]$current.online) { return }

    # The Day 10 lobby uses a simple generated start.bat and does not need the
    # GSC launcher-shell shutdown path. Send a standard RCON stop immediately
    # so rollback never appears hung behind GSC's 180-second stop handler.
    if ($Id -eq "lobby") {
        Day10-DisableLobbyRestartForRollback
        Write-Host "Stopping lobby through direct standard RCON..."
        Day10-DirectRconStop $ServerDir $RconPort
        Day10-WaitOnline $Id $false 120 | Out-Null
        Start-Sleep -Seconds 2
        return
    }

    Write-Host "Stopping $Id through GSC..."
    Day10-Gsc "POST" "/api/server/action" @{id=$Id;action="stop"} | Out-Null
    try {
        Day10-WaitOnline $Id $false 105 | Out-Null
        return
    } catch {
        Write-Host "GSC graceful stop did not finish for $Id; trying direct standard RCON stop without force-kill."
    }
    Day10-DirectRconStop $ServerDir $RconPort
    Day10-WaitOnline $Id $false 120 | Out-Null
}

function Day10-FourRestore {
    param([string]$Root)
    $state = Day10-FourRollbackAssert $Root  # Pre-verify before touching the host.
    Write-Host "DAY10 FOUR-SERVER ROLLBACK START"
    foreach ($entry in @($state.servers)) {
        $current = Day10-State ([string]$entry.id)
        if ($null -eq $current) { throw "GSC server state missing: $($entry.id)" }
        if ([bool]$current.online) {
            Day10-StopForRollback ([string]$entry.id) ([string]$entry.path) ([int]$entry.profile.rcon_port)
        }
    }
    $lobby = Day10-State "lobby"
    if ($null -ne $lobby -and [bool]$lobby.online) {
        Day10-StopForRollback "lobby" ([string]$state.lobby_path) 25579
    }
    foreach($id in @("wild","playground","other")){
        $taskName="Geumyi Day10 Velocity "+$id
        $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if($task){Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop}
    }
    Day10-FourStopProxies $state
    foreach ($entry in $state.servers) {
        $source = Join-Path $Root ("servers\" + $entry.id)
        $destination = [string]$entry.path
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
            throw "Original backend directory missing: $destination"
        }
        # Preserve any test-session changes in quarantine; never wipe them silently.
        $quarantine = Join-Path $Root ("quarantine\" + $entry.id)
        New-Item -ItemType Directory -Force -Path $quarantine | Out-Null
        foreach ($relative in @("server.properties","config","spigot.yml","plugins")) {
            $current = Join-Path $destination $relative
            if (Test-Path -LiteralPath $current) {
                $saved = Join-Path $quarantine $relative
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved) | Out-Null
                Copy-Item -LiteralPath $current -Destination $saved -Recurse -Force -ErrorAction Stop
            }
        }
        foreach ($relative in @("server.properties","config","spigot.yml","plugins")) {
            $target = Join-Path $destination $relative
            $original = Join-Path $source $relative
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            }
            if (Test-Path -LiteralPath $original) {
                Copy-Item -LiteralPath $original -Destination $target -Recurse -Force -ErrorAction Stop
            }
        }
        foreach ($file in @((Get-Content -LiteralPath (Join-Path $source "backup-manifest.json") -Raw | ConvertFrom-Json).files)) {
            $restored = Join-Path $destination ([string]$file.relative)
            if ((Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash -ne [string]$file.sha256) {
                throw "Restored config/plugin hash mismatch: $($entry.id) / $($file.relative)"
            }
        }
    }
    if ($null -ne $lobby) {
        Day10-DisableLobbyRestartForRollback
        $lobbyNow = Day10-State "lobby"
        if ($null -ne $lobbyNow -and [bool]$lobbyNow.online) {
            Day10-StopForRollback "lobby" ([string]$state.lobby_path) 25579
        }
        Day10-WaitOnline "lobby" $false 30 | Out-Null
        Start-Sleep -Seconds 2
        Day10-Gsc "POST" "/api/v4/server-profile" @{action="delete";server=@{id="lobby"}} | Out-Null
    }
    foreach ($entry in $state.servers) {
        Day10-Gsc "POST" "/api/v4/server-profile" @{action="update";server=$entry.profile} | Out-Null
    }
    foreach ($name in @("Geumyi Day10 Velocity Java","Geumyi Day10 Geyser UDP")) {
        Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
    }
    if (Test-Path -LiteralPath ([string]$state.proxy_install_root)) {
        # Quarantine new installation instead of deleting generated Floodgate keys or logs.
        $quarantine = Join-Path $Root "quarantine\deployed-proxies"
        if (Test-Path -LiteralPath $quarantine) { throw "Proxy rollback quarantine already exists" }
        Move-Item -LiteralPath ([string]$state.proxy_install_root) -Destination $quarantine -ErrorAction Stop
    }
    # Lobby is never deleted: its world and logs may contain valuable test data.
    if (Test-Path -LiteralPath ([string]$state.lobby_path)) {
        $quarantine = Join-Path $Root "quarantine\new-lobby"
        if (Test-Path -LiteralPath $quarantine) { throw "Lobby rollback quarantine already exists" }
        Move-Item -LiteralPath ([string]$state.lobby_path) -Destination $quarantine -ErrorAction Stop
    }
    foreach ($entry in $state.servers) {
        if ([bool]$entry.was_online) {
            Day10-Gsc "POST" "/api/server/action" @{id=$entry.id;action="start"} | Out-Null
            Day10-WaitOnline ([string]$entry.id) $true 240 | Out-Null
        }
    }
    Write-Host "DAY10 FOUR-SERVER ROLLBACK VERIFIED; backup and quarantine retained: $Root"
}

if ($SelfTest) {
    $testRoot=Join-Path $env:TEMP ("Day10-RollbackSynthetic-"+[guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $servers=@()
        foreach($id in @("wild","playground","other")){
            $original=Join-Path $testRoot ("servers\"+$id)
            New-Item -ItemType Directory -Path (Join-Path $original "config") -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $original "server.properties"),("server-port="+$id))
            [IO.File]::WriteAllText((Join-Path $original "config\paper-global.yml"),"proxies:")
            $files=@()
            foreach($relative in @("server.properties","config\paper-global.yml")){
                $file=Join-Path $original $relative
                $files += @{relative=$relative;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
            }
            @{files=$files} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $original "backup-manifest.json")
            $servers += @{id=$id;path=(Join-Path $testRoot $id)}
        }
        @{schema=1;servers=$servers} | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $testRoot "four-rollback-state.json")
        $null=Day10-FourRollbackAssert $testRoot
        [IO.File]::AppendAllText((Join-Path $testRoot "servers\other\server.properties"),"tampered")
        $tamperCaught=$false
        try { $null=Day10-FourRollbackAssert $testRoot } catch { $tamperCaught=$true }
        if(-not $tamperCaught){throw "Corrupt backup must block rollback before any host writes"}
        $rconDir = Join-Path $testRoot "rcon"
        New-Item -ItemType Directory -Path $rconDir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $rconDir "server.properties"), "rcon.password=test-password\=", [Text.Encoding]::ASCII)
        if ((Day10-ReadServerPropertyForRollback $rconDir "rcon.password") -ne "test-password=") {
            throw "Java properties escape decoding regression"
        }
        $rconPort = Get-Random -Minimum 30000 -Maximum 45000
        $job = Start-Job -ArgumentList $rconPort -ScriptBlock {
            param($Port)
            function ReadExact($s,[int]$n){
                $b=New-Object byte[] $n; $o=0
                while($o -lt $n){$r=$s.Read($b,$o,$n-$o); if($r -le 0){throw "eof"}; $o+=$r}
                return $b
            }
            function ReadPacket($s){
                $lb=ReadExact $s 4; $len=[BitConverter]::ToInt32($lb,0)
                $p=ReadExact $s $len
                $id=[BitConverter]::ToInt32($p,0); $type=[BitConverter]::ToInt32($p,4)
                $bodyLen=$len-10
                $body=if($bodyLen -gt 0){[Text.Encoding]::UTF8.GetString($p,8,$bodyLen)}else{""}
                return [pscustomobject]@{id=$id;type=$type;body=$body}
            }
            function WritePacket($s,[int]$id,[int]$type,[string]$body){
                $bb=[Text.Encoding]::UTF8.GetBytes($body)
                $ms=New-Object IO.MemoryStream; $bw=New-Object IO.BinaryWriter($ms)
                try{$bw.Write([int](4+4+$bb.Length+2));$bw.Write([int]$id);$bw.Write([int]$type);$bw.Write($bb);$bw.Write([byte]0);$bw.Write([byte]0);$bw.Flush();$out=$ms.ToArray();$s.Write($out,0,$out.Length);$s.Flush()}finally{$bw.Dispose();$ms.Dispose()}
            }
            $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
            $listener.Start()
            try{
                $client=$listener.AcceptTcpClient(); $stream=$client.GetStream()
                try{
                    $auth=ReadPacket $stream
                    if($auth.type -ne 3 -or $auth.body -ne "test-password="){throw "bad auth"}
                    WritePacket $stream $auth.id 0 ""
                    WritePacket $stream $auth.id 2 ""
                    $cmd=ReadPacket $stream
                    $cmd.body
                }finally{$client.Close()}
            }finally{$listener.Stop()}
        }
        Start-Sleep -Milliseconds 500
        try {
            Day10-DirectRconStop $rconDir $rconPort
            if (-not (Wait-Job $job -Timeout 10)) { throw "RCON mock server timeout" }
            $command = Receive-Job $job -ErrorAction Stop | Select-Object -Last 1
            if ([string]$command -ne "stop") { throw "Direct RCON fallback did not send stop" }
        } finally {
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
        Write-Host "DAY10 DIRECT RCON FALLBACK SELFTEST PASS"
        Write-Host "DAY10 FOUR-SERVER ROLLBACK HASH/TAMPER SELFTEST PASS"
    } finally {
        if(Test-Path -LiteralPath $testRoot){
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    exit 0
}
Day10-FourRestore $BackupRoot

exit 0
