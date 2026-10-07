BeforeDiscovery {
    $script:denyCases = @(
        'rm -rf /tmp/x',
        'rm -fr dir',
        'rm -r -f dir',
        'RM -RF dir',
        'git push --force origin main',
        'git push -f origin main',
        'git push --force-with-lease',
        'sudo rm -rf x',
        'rm -Rf x',
        'git push origin main --force',
        '/bin/rm -rf x',
        '\rm -rf x'
    ) | ForEach-Object { @{ Cmd = $_ } }
    $script:allowCases = @(
        'git status',
        'rm file.txt',
        'git push origin main',
        'npm run test',
        'git push --follow-tags',
        'rm -r dir',
        'git rm file',
        'npm run farm'
    ) | ForEach-Object { @{ Cmd = $_ } }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers.ps1')
    $script:hook = Join-Path (Split-Path -Parent $PSScriptRoot) 'claude\hooks\block-dangerous.ps1'
    function script:Invoke-Hook([string]$Command) {
        $json = @{ tool_input = @{ command = $Command } } | ConvertTo-Json -Compress
        Invoke-Script -Path $script:hook -StdinText $json
    }
}

Describe 'block-dangerous hook' {
    It 'deniega: <Cmd>' -ForEach $script:denyCases {
        $r = Invoke-Hook $Cmd
        $r.ExitCode | Should -Be 0
        $o = $r.Stdout | ConvertFrom-Json
        $o.hookSpecificOutput.hookEventName | Should -Be 'PreToolUse'
        $o.hookSpecificOutput.permissionDecision | Should -Be 'deny'
        [string]$o.hookSpecificOutput.permissionDecisionReason | Should -Not -BeNullOrEmpty
    }
    It 'permite: <Cmd>' -ForEach $script:allowCases {
        $r = Invoke-Hook $Cmd
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
        $r = Invoke-Script -Path $script:hook -StdinText '{not json'
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '{}'
        $r.Stderr | Should -BeNullOrEmpty
    }
    It 'devuelve {} si falta tool_input.command' {
        $r = Invoke-Script -Path $script:hook -StdinText '{"tool_name":"Read","tool_input":{"file_path":"a.txt"}}'
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '{}'
        $r.Stderr | Should -BeNullOrEmpty
    }
    It 'funciona con rutas con espacios' {
        $dir = Join-Path $TestDrive 'dir con espacios'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $copy = Join-Path $dir 'hook copy.ps1'
        Copy-Item $script:hook $copy
        $r = Invoke-Script -Path $copy -StdinText ''
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '{}'
    }
}
