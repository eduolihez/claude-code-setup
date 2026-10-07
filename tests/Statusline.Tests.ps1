BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers.ps1')
    $script:hook = Join-Path (Split-Path -Parent $PSScriptRoot) 'claude\hooks\statusline.ps1'
}

Describe 'statusline hook' {
    It 'con JSON valido imprime [modelo] carpeta' {
        $json = @{ model = @{ display_name = 'Opus' }; workspace = @{ current_dir = 'D:\code\demo' } } | ConvertTo-Json -Compress
        $r = Invoke-Script -Path $script:hook -StdinText $json
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -BeExactly '[Opus] demo'
        $r.Stderr | Should -BeNullOrEmpty
    }
    It 'con stdin <Label> imprime la linea minima [claude] y sale con 0' -ForEach @(
        @{ Label = 'vacio'; Text = '' }
        @{ Label = 'JSON invalido'; Text = '{not json' }
    ) {
        $r = Invoke-Script -Path $script:hook -StdinText $Text
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -BeExactly '[claude]'
        $r.Stderr | Should -BeNullOrEmpty
    }
}
