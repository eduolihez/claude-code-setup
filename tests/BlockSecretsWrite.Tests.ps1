BeforeDiscovery {
    # Los secretos se construyen en tiempo de ejecucion para que ningun literal
    # con forma de secreto quede versionado.
    $secrets = @(
        @{ Type = 'AWS';          Secret = ('AKIA' + 'IOSFODNN7EXAMPLE') }
        @{ Type = 'GitHub';       Secret = ('ghp_' + ('a' * 36)) }
        @{ Type = 'Anthropic';    Secret = ('sk-ant-' + ('b' * 24)) }
        @{ Type = 'Slack';        Secret = ('xoxb-' + '1234567890-abcdef') }
        @{ Type = 'clave privada'; Secret = ('-----BEGIN ' + 'RSA PRIVATE KEY-----') }
    )
    $script:denyCases = @()
    foreach ($s in $secrets) {
        foreach ($tool in @(@{ Tool = 'Write'; Field = 'content' }, @{ Tool = 'Edit'; Field = 'new_string' })) {
            $script:denyCases += @{ Type = $s.Type; Secret = $s.Secret; Tool = $tool.Tool; Field = $tool.Field }
        }
    }
    $script:allowCases = @(
        @{ Name = 'codigo normal'; Text = 'function Add($a, $b) { return $a + $b }' }
        @{ Name = 'palabra password en prosa'; Text = 'Recuerda no compartir tu password con nadie.' }
        @{ Name = 'AKIA demasiado corto'; Text = 'AKIA123' }
        @{ Name = 'ghp_ demasiado corto'; Text = 'ghp_abc' }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers.ps1')
    $script:hook = Join-Path (Split-Path -Parent $PSScriptRoot) 'claude\hooks\block-secrets-write.ps1'
    function script:Invoke-Hook([string]$Tool, [string]$Field, [string]$Text) {
        $json = @{ tool_name = $Tool; tool_input = @{ $Field = $Text } } | ConvertTo-Json -Compress
        Invoke-Script -Path $script:hook -StdinText $json
    }
}

Describe 'block-secrets-write hook' {
    It 'deniega secreto <Type> en <Tool> (<Field>)' -ForEach $script:denyCases {
        $r = Invoke-Hook $Tool $Field ('x = "' + $Secret + '"')
        $r.ExitCode | Should -Be 0
        $o = $r.Stdout | ConvertFrom-Json
        $o.hookSpecificOutput.hookEventName | Should -Be 'PreToolUse'
        $o.hookSpecificOutput.permissionDecision | Should -Be 'deny'
        [string]$o.hookSpecificOutput.permissionDecisionReason | Should -BeLike "*$Type*"
        $r.Stdout.Contains($Secret) | Should -BeFalse
    }
    It 'permite: <Name>' -ForEach $script:allowCases {
        $r = Invoke-Hook 'Write' 'content' $Text
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '{}'
    }
    It 'devuelve {} con stdin vacio' {
        $r = Invoke-Script -Path $script:hook -StdinText ''
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '{}'
        $r.Stderr | Should -BeNullOrEmpty
    }
    It 'devuelve {} con JSON invalido' {
        $r = Invoke-Script -Path $script:hook -StdinText '{no es json'
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '{}'
        $r.Stderr | Should -BeNullOrEmpty
    }
    It 'devuelve {} sin content ni new_string' {
        $r = Invoke-Script -Path $script:hook -StdinText '{"tool_name":"Write","tool_input":{"file_path":"a.txt"}}'
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '{}'
        $r.Stderr | Should -BeNullOrEmpty
    }
}
