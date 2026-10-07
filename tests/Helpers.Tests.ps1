BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers.ps1')
}

Describe 'Invoke-Script quoting de argumentos' {
    It 'pasa los argumentos exactamente (espacios, comillas, barra final, +, vacio)' {
        $dir = Join-Path $TestDrive 'dir con espacios'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $script = Join-Path $dir 'echo args.ps1'
        Set-Content -Path $script -Encoding ASCII -Value @(
            'Write-Output ("count=" + $args.Count)',
            'foreach ($a in $args) { Write-Output ("[" + $a + "]") }'
        )
        $given = @('a b', 'say "hi"', 'C:\dir con espacios\', 'x+', '')
        $r = Invoke-Script -Path $script -Arguments $given
        $r.ExitCode | Should -Be 0
        $lines = @($r.Stdout -split "`r?`n" | Where-Object { $_ -ne '' })
        $lines[0] | Should -Be 'count=5'
        for ($i = 0; $i -lt $given.Count; $i++) {
            $lines[$i + 1] | Should -Be ('[' + $given[$i] + ']')
        }
    }
}
