[CmdletBinding()]
param(
  [string]$OutputDir = "",
  [switch]$Synthetic
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Day 12.10 alternate attestation: existing Windows Security WFP 5154/5158.
# NEVER alters audit policy, firewall, processes, services, ports or worlds.
# Security events are historical, not a complete current listener inventory.
$targets = @(
  [pscustomobject]@{port=25570;service="wild_java"},
  [pscustomobject]@{port=25571;service="playground_java"},
  [pscustomobject]@{port=25572;service="other_java"},
  [pscustomobject]@{port=25573;service="lobby_java"},
  [pscustomobject]@{port=25575;service="wild_rcon"},
  [pscustomobject]@{port=25576;service="playground_rcon"},
  [pscustomobject]@{port=25577;service="other_rcon"},
  [pscustomobject]@{port=25579;service="lobby_rcon"}
)
if (-not $OutputDir) {
  $OutputDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Geumyi-Day12-WFP"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$out = Join-Path $OutputDir ("Day12-WFP-Bind-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")

function Get-WfpScope([string]$Address) {
  if ($Address -eq "0.0.0.0" -or $Address -eq "::" -or $Address -eq "0:0:0:0:0:0:0:0") {
    return "WILDCARD"
  }
  $ip = $null
  if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) { return "UNPARSEABLE" }
  if ($ip.IsIPv4MappedToIPv6) { $ip = $ip.MapToIPv4() }
  if ([System.Net.IPAddress]::IsLoopback($ip)) { return "LOOPBACK" }
  return "NON_LOOPBACK_REDACTED"
}


# Categorize failures without exporting OS exception messages or Security logs.
# PowerShell Get-WinEvent often throws NoMatchingEventsFound when the XPath is valid
# but no events are retained. The previous version erroneously merged that with access denied.
function Get-WfpEventQueryErrorCategory($Record) {
  $fqid = [string]$Record.FullyQualifiedErrorId
  $ex = $Record.Exception
  if ($fqid -match "(?i)NoMatchingEventsFound") {
    return "NO_RETAINED_MATCHING_WFP_EVENTS"
  }
  if ($ex -is [System.UnauthorizedAccessException] -or
      $ex -is [System.Security.SecurityException] -or
      $fqid -match "(?i)(AccessDenied|Unauthorized|PermissionDenied)") {
    return "SECURITY_LOG_ACCESS_DENIED"
  }
  if ($null -ne $ex -and (($ex.HResult -band 65535) -eq 5)) {
    return "SECURITY_LOG_ACCESS_DENIED"
  }
  return "WFP_EVENT_QUERY_FAILED"
}

function Convert-WfpEvent([string]$Xml) {
  [xml]$d = $Xml
  # Explicit XmlDocument XPath avoids PowerShell XML adapter collapsing
  # EventID to a string (with no InnerText property under StrictMode).
  $eventIdNode = $d.SelectSingleNode("/*[local-name()='Event']/*[local-name()='System']/*[local-name()='EventID']")
  if ($null -eq $eventIdNode) { throw "EVENT_ID_MISSING" }
  $id = [int]$eventIdNode.InnerText
  if ($id -notin @(5154, 5158)) { throw "UNEXPECTED_EVENT_ID" }
  $fields = @{}
  $nodes = $d.SelectNodes("/*[local-name()='Event']/*[local-name()='EventData']/*[local-name()='Data']")
  foreach ($node in $nodes) {
    $fields[[string]$node.GetAttribute("Name")] = [string]$node.InnerText
  }
  foreach ($required in @("ProcessId","SourcePort","SourceAddress","Protocol","Application")) {
    if (-not $fields.ContainsKey($required)) { throw "EVENT_FIELD_MISSING" }
  }
  $pidText = [string]$fields.ProcessId
  $eventPid = 0L
  if ($pidText.StartsWith("0x", [StringComparison]::OrdinalIgnoreCase)) {
    $eventPid = [Convert]::ToInt64($pidText.Substring(2), 16)
  } elseif (-not [long]::TryParse($pidText, [ref]$eventPid)) {
    throw "EVENT_PID_NOT_NUMERIC"
  }
  $port = 0
  if (-not [int]::TryParse($fields.SourcePort, [ref]$port)) { throw "EVENT_PORT_NOT_NUMERIC" }
  $timeNode = $d.SelectSingleNode("/*[local-name()='Event']/*[local-name()='System']/*[local-name()='TimeCreated']")
  if ($null -eq $timeNode) { throw "EVENT_TIME_MISSING" }
  $when = [DateTimeOffset]::Parse(
    [string]$timeNode.GetAttribute("SystemTime"),
    [System.Globalization.CultureInfo]::InvariantCulture
  )
  return [pscustomobject]@{
    event_id=$id
    port=$port
    pid=$eventPid
    protocol=([string]$fields.Protocol)
    scope=(Get-WfpScope ([string]$fields.SourceAddress))
    is_java=([string]$fields.Application -match '(?i)(?:^|[\\/])javaw?\.exe$')
    time=$when
  }
}

function Get-WfpSummary($Records, $LiveJava, $Plan) {
  $summary = @()
  foreach ($target in @($Plan)) {
    $events = @()
    foreach ($event in @($Records)) {
      if ($null -eq $event -or $event.port -ne [int]$target.port -or $event.protocol -ne "6" -or -not $event.is_java) { continue }
      $matching = @($LiveJava | Where-Object {
        [long]$_.pid -eq [long]$event.pid -and $event.time -ge $_.start.AddSeconds(-10)
      })
      if ($matching.Count -eq 0) { continue } # Prevent historical PID reuse.
      $events += $event
    }
    $listen = @($events | Where-Object { $_.event_id -eq 5154 })
    $bind = @($events | Where-Object { $_.event_id -eq 5158 })
    $scopes = @($events | ForEach-Object { $_.scope } | Sort-Object -Unique)
    $unsafe = @($events | Where-Object { $_.scope -ne "LOOPBACK" }).Count
    $state = if ($unsafe -gt 0) { "REVIEW_NON_LOOPBACK_OR_UNPARSEABLE" }
      elseif ($listen.Count -gt 0 -and $bind.Count -gt 0) { "HISTORICAL_LOOPBACK_LISTEN_AND_BIND" }
      elseif ($listen.Count -gt 0 -or $bind.Count -gt 0) { "HISTORICAL_LOOPBACK_PARTIAL" }
      else { "NO_CURRENT_PROCESS_EVENT" }
    $summary += [ordered]@{
      service=[string]$target.service
      port=[int]$target.port
      finding=$state
      listen_events=$listen.Count
      bind_events=$bind.Count
      scopes=$scopes
    }
  }
  return @($summary)
}

if ($Synthetic) {
  function New-SyntheticEvent([int]$Id, [string]$Address, [string]$SyntheticPid, [int]$Port, [string]$App, [DateTimeOffset]$When) {
    $date = $When.UtcDateTime.ToString("o")
    $esc = [System.Security.SecurityElement]::Escape($App)
    return @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
<System><EventID>$Id</EventID><TimeCreated SystemTime="$date" /></System>
<EventData><Data Name="ProcessId">$SyntheticPid</Data><Data Name="Application">$esc</Data>
<Data Name="SourceAddress">$Address</Data><Data Name="SourcePort">$Port</Data>
<Data Name="Protocol">6</Data></EventData></Event>
"@
  }
  $start = [DateTimeOffset]::UtcNow.AddMinutes(-15)
  $now = [DateTimeOffset]::UtcNow
  $fixture = @(
    (Convert-WfpEvent (New-SyntheticEvent 5154 "127.0.0.1" "1001" 25570 "C:\Program Files\Java\bin\java.exe" $now)),
    (Convert-WfpEvent (New-SyntheticEvent 5158 "::1" "0x3e9" 25570 "C:\Program Files\Java\bin\java.exe" $now)),
    (Convert-WfpEvent (New-SyntheticEvent 5154 "0.0.0.0" "1002" 25571 "C:\Java\bin\javaw.exe" $now)),
    (Convert-WfpEvent (New-SyntheticEvent 5154 "127.0.0.1" "1003" 25572 "C:\Java\bin\java.exe" $start.AddHours(-2)))
  )
  $processes = @(
    [pscustomobject]@{pid=1001L;start=$start},
    [pscustomobject]@{pid=1002L;start=$start},
    [pscustomobject]@{pid=1003L;start=$start}
  )
  $rows = @(Get-WfpSummary -Records $fixture -LiveJava $processes -Plan $targets)
  $a = @($rows | Where-Object {$_.port -eq 25570})[0]
  $b = @($rows | Where-Object {$_.port -eq 25571})[0]
  $c = @($rows | Where-Object {$_.port -eq 25572})[0]
  $d = @($rows | Where-Object {$_.port -eq 25573})[0]
  if ($a.finding -ne "HISTORICAL_LOOPBACK_LISTEN_AND_BIND" -or
      $b.finding -ne "REVIEW_NON_LOOPBACK_OR_UNPARSEABLE" -or
      $c.finding -ne "NO_CURRENT_PROCESS_EVENT" -or
      $d.finding -ne "NO_CURRENT_PROCESS_EVENT" -or
      (Get-WfpScope "192.0.2.1") -ne "NON_LOOPBACK_REDACTED" -or
      (Get-WfpScope "::") -ne "WILDCARD") {
    throw "WFP_SYNTHETIC_FAIL_CLOSED_CLASSIFIER_FAILED"
  }
  # Synthetic exception classification does not access the Windows Security log.
  $erNo = [System.Management.Automation.ErrorRecord]::new(
    [System.InvalidOperationException]::new("no matches"), "NoMatchingEventsFound",
    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
  $erDenied = [System.Management.Automation.ErrorRecord]::new(
    [System.UnauthorizedAccessException]::new("access denied"), "PermissionDenied",
    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
  $erBad = [System.Management.Automation.ErrorRecord]::new(
    [System.InvalidOperationException]::new("bad query"), "InvalidArgument",
    [System.Management.Automation.ErrorCategory]::InvalidArgument, $null)
  if ((Get-WfpEventQueryErrorCategory $erNo) -ne "NO_RETAINED_MATCHING_WFP_EVENTS" -or
      (Get-WfpEventQueryErrorCategory $erDenied) -ne "SECURITY_LOG_ACCESS_DENIED" -or
      (Get-WfpEventQueryErrorCategory $erBad) -ne "WFP_EVENT_QUERY_FAILED") {
    throw "WFP_SYNTHETIC_ERROR_CATEGORY_FAILED"
  }
  $result = [ordered]@{
    schema=1;phase="12.10-wfp";synthetic=$true;read_only=$true
    result="SYNTHETIC_PASS";mutation_performed=$false;secrets_exported=$false
    scenarios=@("current-pid-loopback-v4-v6", "hexadecimal-pid", "wildcard-rejected",
                "stale-pid-rejected", "missing-events-unknown",
                "missing-history-vs-access-denied-vs-query-error")
    summary=$rows
    canonical_backend_ports_private="UNCHANGED_FAIL"
  }
  $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $out -Encoding UTF8
  Write-Host ("WFP historical event fixture PASS: "+$out)
  exit 0
}

$status = "REVIEW_REQUIRED"
$errorCategory = "NONE"
$records = @()
$processes = @()
$limitReached = $false
$processStatus = "NOT_CHECKED"
$eventQueryStatus = "NOT_RUN"
try {
  if (-not [Environment]::OSVersion.Platform.ToString().Equals("Win32NT")) {
    throw "WINDOWS_REQUIRED"
  }
  $now = [DateTimeOffset]::UtcNow
  # Keep only currently running Java process generations; never output raw paths.
  $java = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'" -ErrorAction Stop)
  $processStatus = "CAPTURED"
  foreach ($p in $java) {
    if ($null -eq $p.CreationDate) { continue }
    $start = [DateTimeOffset]([datetime]$p.CreationDate)
    $processes += [pscustomobject]@{pid=[long]$p.ProcessId;start=$start}
  }
  # Filter in Windows Event Log XPath before retrieval to avoid exporting unrelated
  # Security records. Reading may require elevated log-read permission.
  $filters = @(foreach ($t in $targets) { "Data[@Name='SourcePort']='$( [int]$t.port )'" })
  $portClause = $filters -join " or "
  $windowMs = 7 * 24 * 3600 * 1000
  $xpath = "*[System[(EventID=5154 or EventID=5158) and TimeCreated[timediff(@SystemTime) <= $windowMs]] and EventData[$portClause]]"
  $maxEvents = 2500
  try {
    $events = @(Get-WinEvent -LogName Security -FilterXPath $xpath -MaxEvents $maxEvents -ErrorAction Stop)
    $eventQueryStatus = "CAPTURED"
  } catch {
    $errorCategory = Get-WfpEventQueryErrorCategory $_
    if ($errorCategory -eq "NO_RETAINED_MATCHING_WFP_EVENTS") {
      $eventQueryStatus = "NO_MATCHING_EVENTS"
      $status = "NO_EVIDENCE"
    } else {
      $eventQueryStatus = "ERROR"
      $status = "UNAVAILABLE"
    }
    $events = @()
  }
  $limitReached = $events.Count -ge $maxEvents
  foreach ($ev in $events) {
    try {
      $rec = Convert-WfpEvent ([string]$ev.ToXml())
      if (@($targets | Where-Object {$_.port -eq $rec.port}).Count -gt 0) {
        $records += $rec
      }
    } catch {
      $errorCategory = "PARTIAL_WFP_EVENT_PARSE_ERROR"
    }
  }
    if ($errorCategory -eq "PARTIAL_WFP_EVENT_PARSE_ERROR") {
      $status = "UNAVAILABLE"
    }
} catch {
  $status = "UNAVAILABLE"
  if ($processStatus -ne "CAPTURED") {
    $processStatus = "ERROR"
    $errorCategory = "JAVA_PROCESS_INVENTORY_FAILED"
  } else {
    $errorCategory = "UNHANDLED_WFP_READER_ERROR"
  }
}

$rows = @(Get-WfpSummary -Records $records -LiveJava $processes -Plan $targets)
if ($limitReached) { $errorCategory = "EVENT_QUERY_TRUNCATED"; $status = "REVIEW_REQUIRED" }
if ($status -eq "REVIEW_REQUIRED" -and $records.Count -eq 0 -and $errorCategory -eq "NONE") {
  $errorCategory = "NO_RETAINED_MATCHING_WFP_EVENTS"
}
$report = [ordered]@{
  schema=1;phase="12.10-wfp";generated_at=(Get-Date).ToString("o")
  result=$status;error_category=$errorCategory
  process_inventory_status=$processStatus
  event_query_status=$eventQueryStatus
  synthetic=$false;read_only=$true
  provider="Existing Windows Security WFP audit event 5154/5158"
  audit_policy_changed=$false
  event_scan_limit=2500;event_count=$records.Count;process_generations_seen=$processes.Count
  query_truncated=$limitReached
  observations=$rows
  canonical_backend_ports_private="UNCHANGED_FAIL"
  notes=@(
    "Historical WFP bind/listen event evidence only; does NOT prove all currently open sockets are loopback.",
    "Missing events may mean auditing was disabled, logs rotated, permissions insufficient or process was started earlier.",
    "A 5154/5158 wildcard or non-loopback observation requires security review.",
    "No auditpol /set, firewall, TCP enumeration, port connections, service restarts or world/backup changes.",
    "Only service, port, scope category and counts are exported; no raw IP, paths, process IDs or log messages."
  )
  mutation_performed=$false;secrets_exported=$false
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("WFP independent audit: "+$status+" / "+$errorCategory)
Write-Host ("Report: "+$out)
if ($status -eq "UNAVAILABLE" -or $status -eq "NO_EVIDENCE") { exit 2 }
exit 0
