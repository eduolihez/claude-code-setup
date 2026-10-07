# PreToolUse hook: deniega "rm -rf" (y variantes) y "git push --force/-f".
# Contrato: stdin {"tool_input":{"command":"..."}} -> stdout "{}" o JSON de deny.
# Ante entrada vacia o invalida no bloquea: imprime "{}" y sale con 0.

function Get-DenyReason([string]$Cmd) {
    # rm (incluido /bin/rm o rm escapado con barra inversa) con flags recursivo (-r/-R/--recursive)
    # y force (-f/--force), en cualquier orden o combinacion (-rf, -fr, -r -f, -Rf). Insensible a mayusculas.
    $rm = [regex]::Match($Cmd, '(?i)(?:^|[\s;&|(/\\])rm((?:\s+--?[a-z][a-z-]*)+)')
    if ($rm.Success) {
        $flags = $rm.Groups[1].Value
        $recursive = $flags -match '(?i)\s-[a-z]*r|\s--recursive'
        $force = $flags -match '(?i)\s-[a-z]*f|\s--force'
        if ($recursive -and $force) {
            return 'Bloqueado: rm recursivo y forzado (rm -rf). Elimina de forma explicita y acotada.'
        }
    }
    # git push --force, --force-with-lease o -f (flag corto, solo o combinado).
    if ($Cmd -match '(?i)\bgit\s+push\b.*\s(--force\S*|-[a-z]*f[a-z]*)(\s|$)') {
        return 'Bloqueado: git push forzado (--force / --force-with-lease / -f). Hazlo manualmente si es necesario.'
    }
    return $null
}

$cmd = $null
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $data = $raw | ConvertFrom-Json
        $cmd = [string]$data.tool_input.command
    }
}
catch {
    $cmd = $null
}

$reason = $null
if (-not [string]::IsNullOrEmpty($cmd)) { $reason = Get-DenyReason $cmd }

if ($reason) {
    $output = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
    }
    $output | ConvertTo-Json -Compress
}
else {
    '{}'
}
exit 0
