BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers.ps1')
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:installer = Join-Path $script:repoRoot 'install.ps1'
    $script:src = Join-Path $script:repoRoot 'claude'

    function Get-FileHashValue([string]$Path) {
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    # Lista "ruta relativa=hash" ordenada de todos los archivos bajo $Root.
    function Get-TreeHash([string]$Root) {
        $prefix = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\') + '\'
        $items = Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object {
            $_.FullName.Substring($prefix.Length) + '=' + (Get-FileHashValue $_.FullName)
        }
        return (@($items) | Sort-Object) -join "`n"
    }

    # Archivos gestionados (relativos a claude/): CLAUDE.md, settings.json, agents, hooks y skills.
    function Get-ManagedFiles {
        $list = @('CLAUDE.md', 'settings.json')
        foreach ($d in 'agents', 'hooks') {
            $list += @(Get-ChildItem -LiteralPath (Join-Path $script:src $d) -File | ForEach-Object { "$d\$($_.Name)" })
        }
        $prefix = $script:src.TrimEnd('\') + '\'
        foreach ($s in Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory) {
            $list += @(Get-ChildItem -LiteralPath $s.FullName -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix.Length) })
        }
        return $list
    }

    function New-Target([string]$Path) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        foreach ($d in 'projects', 'sessions', 'skills\gstack', 'agents') {
            New-Item -ItemType Directory -Force -Path (Join-Path $Path $d) | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $Path '.credentials.json') -Value '{"secret":"x"}'
        Set-Content -LiteralPath (Join-Path $Path 'history.jsonl') -Value '{"h":1}'
        Set-Content -LiteralPath (Join-Path $Path 'projects\p.txt') -Value 'proyecto'
        Set-Content -LiteralPath (Join-Path $Path 'sessions\s.json') -Value '{"s":1}'
        Set-Content -LiteralPath (Join-Path $Path 'skills\gstack\SKILL.md') -Value 'ajena'
        Set-Content -LiteralPath (Join-Path $Path 'agents\mine.md') -Value 'mio'
    }

    function Invoke-Install([string]$Target, [string[]]$Extra = @()) {
        Invoke-Script -Path $script:installer -Arguments (@('-TargetDir', $Target, '-Copy') + $Extra)
    }

    function Get-BackupDirs([string]$Target) {
        $b = Join-Path $Target 'backups'
        if (-not (Test-Path -LiteralPath $b)) { return @() }
        return @(Get-ChildItem -LiteralPath $b -Directory)
    }
}

Describe 'install.ps1 (modo copia)' {
    It 'copia todas las rutas gestionadas identicas al repo' {
        $t = Join-Path $TestDrive 'copia'
        New-Target $t
        $files = Get-ManagedFiles
        $files.Count | Should -BeGreaterThan 5
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        foreach ($f in $files) {
            $dst = Join-Path $t $f
            Test-Path -LiteralPath $dst | Should -BeTrue -Because $f
            Get-FileHashValue $dst | Should -Be (Get-FileHashValue (Join-Path $script:src $f)) -Because $f
        }
    }

    It 'mueve un CLAUDE.md existente a backups/setup-TIMESTAMP/CLAUDE.md' {
        $t = Join-Path $TestDrive 'backup'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'contenido previo distinto'
        $before = Get-FileHashValue (Join-Path $t 'CLAUDE.md')
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        $dirs = Get-BackupDirs $t
        $dirs.Count | Should -Be 1
        $dirs[0].Name | Should -Match '^setup-\d{8}-\d{6}'
        $bk = Join-Path $dirs[0].FullName 'CLAUDE.md'
        Test-Path -LiteralPath $bk | Should -BeTrue
        Get-FileHashValue $bk | Should -Be $before
        Get-FileHashValue (Join-Path $t 'CLAUDE.md') | Should -Be (Get-FileHashValue (Join-Path $script:src 'CLAUDE.md'))
    }

    It 'no modifica credenciales, historial, proyectos, sesiones ni skills y agentes ajenos' {
        $t = Join-Path $TestDrive 'ajenos'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'previo'
        $others = '.credentials.json', 'history.jsonl', 'projects\p.txt', 'sessions\s.json', 'skills\gstack\SKILL.md', 'agents\mine.md'
        $before = @{}
        foreach ($o in $others) { $before[$o] = Get-FileHashValue (Join-Path $t $o) }
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        foreach ($o in $others) {
            Get-FileHashValue (Join-Path $t $o) | Should -Be $before[$o] -Because $o
        }
        $dirs = Get-BackupDirs $t
        $dirs.Count | Should -Be 1
        $inBackup = @(Get-ChildItem -LiteralPath $dirs[0].FullName -Recurse -File | ForEach-Object { $_.Name })
        $inBackup.Count | Should -BeGreaterThan 0
        foreach ($n in '.credentials.json', 'history.jsonl', 'p.txt', 's.json', 'mine.md') {
            $inBackup | Should -Not -Contain $n
        }
        Test-Path -LiteralPath (Join-Path $dirs[0].FullName 'skills\gstack') | Should -BeFalse
    }

    It '-DryRun no cambia nada' {
        $t = Join-Path $TestDrive 'dry'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'previo'
        $before = Get-TreeHash $t
        $r = Invoke-Install $t @('-DryRun')
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        Get-TreeHash $t | Should -Be $before
        Test-Path -LiteralPath (Join-Path $t 'backups') | Should -BeFalse
        $r.Stdout | Should -Match '\[DryRun\]'
    }

    It 'es idempotente' {
        $t = Join-Path $TestDrive 'idem'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'previo'
        (Invoke-Install $t).ExitCode | Should -Be 0
        $names = @(Get-BackupDirs $t | ForEach-Object { $_.Name })
        $names.Count | Should -Be 1
        $tree = Get-TreeHash $t
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        @(Get-BackupDirs $t | ForEach-Object { $_.Name }) | Should -Be $names
        Get-TreeHash $t | Should -Be $tree
    }

    It 'funciona con TargetDir con espacios y caracteres no ASCII' {
        $t = Join-Path $TestDrive ('mi carpeta ca' + [char]0xF1 + 'on [x]\sub dir')
        $files = Get-ManagedFiles
        $files.Count | Should -BeGreaterThan 5
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because ($r.Stdout + $r.Stderr)
        foreach ($f in $files) {
            Get-FileHashValue (Join-Path $t $f) | Should -Be (Get-FileHashValue (Join-Path $script:src $f)) -Because $f
        }
    }

    It 'falla con exit distinto de cero si TargetDir es un archivo' {
        $t = Join-Path $TestDrive 'archivo.txt'
        Set-Content -LiteralPath $t -Value 'soy un archivo'
        $before = Get-FileHashValue $t
        $r = Invoke-Install $t
        $r.ExitCode | Should -Not -Be 0
        (Get-Item -LiteralPath $t).PSIsContainer | Should -BeFalse
        Get-FileHashValue $t | Should -Be $before
        Test-Path -LiteralPath (Join-Path $TestDrive 'backups') | Should -BeFalse
    }
}
