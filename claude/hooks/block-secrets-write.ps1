# PreToolUse hook (Write|Edit): deniega escribir secretos reconocibles.
# Contrato: stdin {"tool_input":{"content"|"new_string":"..."}} -> stdout "{}" o JSON de deny.
# La razon nombra el tipo de secreto y nunca lo reproduce.
# Ante entrada vacia o invalida no bloquea: imprime "{}" y sale con 0.

$script:SecretPatterns = @(
    @{ Name = 'clave de AWS';              Pattern = 'AKIA[0-9A-Z]{16}' }
    @{ Name = 'token de GitHub';           Pattern = 'gh[pousr]_[A-Za-z0-9]{36,}' }
    @{ Name = 'clave de API de Anthropic'; Pattern = 'sk-ant-[A-Za-z0-9_-]{20,}' }
    @{ Name = 'token de Slack';            Pattern = 'xox[baprs]-[A-Za-z0-9-]{10,}' }
    @{ Name = 'clave privada';             Pattern = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' }
)

function Get-DenyReason([string]$Text) {
    foreach ($p in $script:SecretPatterns) {
        if ($Text -cmatch $p.Pattern) {
            return ('Bloqueado: el contenido parece incluir ' + $p.Name + '. Usa una variable de entorno o un gestor de secretos.')
        }
    }
    return $null
}

$text = $null
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $data = $raw | ConvertFrom-Json
        $text = [string]$data.tool_input.content
        if ([string]::IsNullOrEmpty($text)) { $text = [string]$data.tool_input.new_string }
    }
}
catch {
    $text = $null
}

$reason = $null
if (-not [string]::IsNullOrEmpty($text)) { $reason = Get-DenyReason $text }

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
