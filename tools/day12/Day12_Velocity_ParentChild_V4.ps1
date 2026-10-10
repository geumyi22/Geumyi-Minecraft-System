# Side-effect-free validator for the observed Day12 3 scheduled tasks + 3 child Java PIDs.
# This function does not read/modify host state; callers supply process rows and UDP ownership.
function Resolve-ThreeProxyPairs {
    param([object[]]$Candidates,[hashtable]$UdpOwners)
    $ids = @('wild','playground','other')
    if (@($Candidates).Count -ne 6) { throw 'EXPECTED_SIX_VELOCITY_PROCESS_CANDIDATES' }
    $pids = @($Candidates | ForEach-Object { [int]$_.pid })
    if (@($pids | Select-Object -Unique).Count -ne 6 -or @($pids | Where-Object { $_ -le 4 }).Count -gt 0) {
        throw 'PROCESS_PID_DUPLICATE_OR_INVALID'
    }
    foreach ($row in $Candidates) {
        if ([string]$row.kind -cne 'TASK_STYLE_RELATIVE_JAR') { throw 'UNEXPECTED_VELOCITY_COMMAND_SHAPE' }
    }
    $roots = @($Candidates | Where-Object { [int]$_.parent_pid -notin $pids })
    $leaves = @($Candidates | Where-Object { [int]$_.parent_pid -in $pids })
    if ($roots.Count -ne 3 -or $leaves.Count -ne 3) { throw 'EXPECTED_THREE_ROOT_AND_THREE_CHILD_PIDS' }
    if ($UdpOwners.Count -ne 3) { throw 'EXPECTED_THREE_UDP_OWNER_KEYS' }
    $usedRoots = @{}
    $usedLeaves = @{}
    $pairs = @()
    foreach ($id in $ids) {
        if (-not $UdpOwners.ContainsKey($id)) { throw ($id+':UDP_OWNER_NOT_PRESENT') }
        $childPid = [int]$UdpOwners[$id]
        $child = @($leaves | Where-Object { [int]$_.pid -eq $childPid })
        if ($child.Count -ne 1) { throw ($id+':UDP_OWNER_NOT_UNIQUE_CHILD') }
        $rootPid = [int]$child[0].parent_pid
        $root = @($roots | Where-Object { [int]$_.pid -eq $rootPid })
        if ($root.Count -ne 1) { throw ($id+':UDP_CHILD_PARENT_NOT_ROOT') }
        if ($usedRoots.ContainsKey([string]$rootPid) -or $usedLeaves.ContainsKey([string]$childPid)) {
            throw 'PARENT_CHILD_PID_REUSED_BETWEEN_PROXIES'
        }
        $children = @($leaves | Where-Object { [int]$_.parent_pid -eq $rootPid })
        if ($children.Count -ne 1) { throw 'EXTRA_CHILD_PID_FOR_ROOT' }
        $usedRoots[[string]$rootPid]=$true
        $usedLeaves[[string]$childPid]=$true
        $pairs += [pscustomobject]@{ id=$id; root_pid=$rootPid; child_pid=$childPid }
    }
    if ($usedRoots.Count -ne 3 -or $usedLeaves.Count -ne 3) { throw 'PROCESS_PAIRS_INCOMPLETE' }
    return $pairs
}
