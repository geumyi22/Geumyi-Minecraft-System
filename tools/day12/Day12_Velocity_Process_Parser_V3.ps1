function Get-JarArgument([string]$CommandLine) {
    # Accept exactly one -jar argument, quoted absolute jar paths, or the relative
    # velocity.jar used by the Day10 ScheduledTask action. Never execute this text.
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $matches = [regex]::Matches($CommandLine, '(?i)(?:^|\s)-jar\s+(?:"([^"\r\n]+)"|([^\s"]+))(?=\s|$)')
    if ($matches.Count -ne 1) { return $null }
    $argument = if ($matches[0].Groups[1].Success) {
        $matches[0].Groups[1].Value
    } else {
        $matches[0].Groups[2].Value
    }
    if ([IO.Path]::GetFileName($argument) -ine 'velocity.jar') { return $null }
    return $argument
}
function Classify-JarArgument([string]$Argument) {
    # Output is a simple category; host paths and complete command lines are
    # never included in operator JSON. Explicitly ban unknown absolute paths.
    if ([string]::IsNullOrWhiteSpace($Argument)) { return 'NOT_VELOCITY' }
    if ($Argument -in @('velocity.jar','.\velocity.jar','./velocity.jar')) {
        return 'TASK_STYLE_RELATIVE_JAR'
    }
    if (-not [IO.Path]::IsPathRooted($Argument)) { return 'UNEXPECTED_RELATIVE_JAR' }
    $full = try { [IO.Path]::GetFullPath($Argument) } catch { return 'INVALID_ABSOLUTE_JAR' }
    foreach ($p in $proxyPorts) {
        $expected = [IO.Path]::GetFullPath((Join-Path (Join-Path $ProxyRoot $p.id) 'velocity.jar'))
        if ($full -ieq $expected) { return ('EXPECTED_ABSOLUTE_' + $p.id.ToUpperInvariant()) }
    }
    return 'OUTSIDE_EXPECTED_PROXY_ROOT'
}
