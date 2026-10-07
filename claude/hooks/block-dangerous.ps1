$input_json = [Console]::In.ReadToEnd() | ConvertFrom-Json
$cmd = $input_json.tool_input.command

if ($cmd -match 'rm\s+-rf|git\s+push\s+--force') {
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
        }
    }
    $output | ConvertTo-Json -Compress
} else {
    "{}"
}
