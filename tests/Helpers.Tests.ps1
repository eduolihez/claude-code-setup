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

Describe 'Invoke-Script stdin sin BOM' {
    It 'no antepone BOM a stdin aunque la codificacion de entrada de la consola del padre sea UTF-8' {
        # En los runners de CI la consola del padre es UTF-8 (cp 65001) y .NET Framework
        # emite un BOM al crear el flujo de entrada del proceso hijo.
        $probe = Join-Path $TestDrive 'bom-probe.ps1'
        Set-Content -Path $probe -Encoding ASCII -Value '$t = [Console]::In.ReadToEnd(); [string][int]$t[0]'
        $prev = $null
        $switched = $false
        try {
            $prev = [Console]::InputEncoding
            [Console]::InputEncoding = [System.Text.Encoding]::UTF8
            $switched = $true
        }
        catch { }
        if (-not $switched) {
            Set-ItResult -Skipped -Because 'no se puede cambiar la codificacion de entrada de la consola'
            return
        }
        try {
            $r = Invoke-Script -Path $probe -StdinText '{"a":1}'
        }
        finally {
            [Console]::InputEncoding = $prev
        }
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be '123'
    }
}
