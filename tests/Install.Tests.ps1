BeforeDiscovery {
    # Sondeo: se puede crear un symlink en este entorno? (en Windows requiere admin o modo desarrollador)
    $script:canSymlink = $false
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ('symprobe-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $probe | Out-Null
        $f = Join-Path $probe 'f.txt'
        Set-Content -LiteralPath $f -Value 'x'
        New-Item -ItemType SymbolicLink -Path (Join-Path $probe 'l.txt') -Value $f -ErrorAction Stop | Out-Null
        $script:canSymlink = $true
    }
    catch { $script:canSymlink = $false }
    finally {
        if (Test-Path -LiteralPath $probe) {
            $l = Join-Path $probe 'l.txt'
            if (Test-Path -LiteralPath $l) { [System.IO.File]::Delete($l) }
            Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

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
        $dirsBefore = @(Get-ChildItem -LiteralPath $TestDrive -Directory | ForEach-Object { $_.Name })
        $r = Invoke-Install $t
        $r.ExitCode | Should -Not -Be 0
        (Get-Item -LiteralPath $t).PSIsContainer | Should -BeFalse
        Get-FileHashValue $t | Should -Be $before
        @(Get-ChildItem -LiteralPath $TestDrive -Directory | ForEach-Object { $_.Name }) | Should -Be $dirsBefore
    }

    It 'mueve una skill del repo modificada a backups y deja la copia exacta, sin tocar skills ajenas' {
        $t = Join-Path $TestDrive 'skillbk'
        New-Target $t
        $skill = (Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory | Select-Object -First 1).Name
        $sd = Join-Path $t "skills\$skill"
        New-Item -ItemType Directory -Force -Path $sd | Out-Null
        Set-Content -LiteralPath (Join-Path $sd 'SKILL.md') -Value 'modificada en destino'
        Set-Content -LiteralPath (Join-Path $sd 'extra.md') -Value 'extra'
        $modHash = Get-FileHashValue (Join-Path $sd 'SKILL.md')
        $gst = Get-FileHashValue (Join-Path $t 'skills\gstack\SKILL.md')
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        $dirs = Get-BackupDirs $t
        $dirs.Count | Should -Be 1
        $bk = Join-Path $dirs[0].FullName "skills\$skill"
        Get-FileHashValue (Join-Path $bk 'SKILL.md') | Should -Be $modHash
        Test-Path -LiteralPath (Join-Path $bk 'extra.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $sd 'extra.md') | Should -BeFalse
        $repoSkill = Join-Path $script:src "skills\$skill"
        $repoFiles = @(Get-ChildItem -LiteralPath $repoSkill -Recurse -File)
        $repoFiles.Count | Should -BeGreaterThan 0
        foreach ($f in $repoFiles) {
            $rel = $f.FullName.Substring($repoSkill.TrimEnd('').Length + 1)
            Get-FileHashValue (Join-Path $sd $rel) | Should -Be (Get-FileHashValue $f.FullName) -Because $rel
        }
        Get-FileHashValue (Join-Path $t 'skills\gstack\SKILL.md') | Should -Be $gst
    }

    It 'la primera adopcion de skills identicas al repo las guarda en backup y reinstalar no crea otro' {
        $t = Join-Path $TestDrive 'skillsame'
        New-Target $t
        $skillsDst = Join-Path $t 'skills'
        $skills = @(Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory)
        $skills.Count | Should -BeGreaterThan 0
        foreach ($s in $skills) {
            Copy-Item -LiteralPath $s.FullName -Destination (Join-Path $skillsDst $s.Name) -Recurse
        }
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        $dirs = @(Get-BackupDirs $t)
        $dirs.Count | Should -Be 1
        foreach ($s in $skills) {
            Test-Path -LiteralPath (Join-Path $dirs[0].FullName "skills\$($s.Name)\SKILL.md") | Should -BeTrue -Because $s.Name
        }
        $tree = Get-TreeHash $t
        $r2 = Invoke-Install $t
        $r2.ExitCode | Should -Be 0 -Because $r2.Stdout
        @(Get-BackupDirs $t).Count | Should -Be 1
        Get-TreeHash $t | Should -Be $tree
    }
}

Describe 'install.ps1 (enlaces, fallback y -Uninstall)' {
    BeforeAll {
        function Invoke-Link([string]$Target, [string[]]$Extra = @(), [hashtable]$Env = @{}) {
            $saved = @{}
            foreach ($k in $Env.Keys) {
                $saved[$k] = [Environment]::GetEnvironmentVariable($k)
                [Environment]::SetEnvironmentVariable($k, $Env[$k])
            }
            try { Invoke-Script -Path $script:installer -Arguments (@('-TargetDir', $Target) + $Extra) }
            finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
        }

        function Test-IsReparse([string]$Path) {
            return (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        }

        # Entradas gestionadas de primer nivel (relativas a claude/): archivos y carpetas de skills.
        function Get-ManagedEntries {
            $list = @('CLAUDE.md', 'settings.json')
            foreach ($d in 'agents', 'hooks') {
                $list += @(Get-ChildItem -LiteralPath (Join-Path $script:src $d) -File | ForEach-Object { "$d\$($_.Name)" })
            }
            $list += @(Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory | ForEach-Object { "skills\$($_.Name)" })
            return $list
        }

        function New-FakeBackup([string]$Target, [string]$Name = 'setup-20260101-000000') {
            $bk = Join-Path $Target "backups\$Name"
            New-Item -ItemType Directory -Force -Path $bk | Out-Null
            Set-Content -LiteralPath (Join-Path $bk 'CLAUDE.md') -Value 'MARCADOR-PREVIO'
            return $bk
        }
    }

    It 'con CLAUDE_SETUP_NO_SYMLINK=1 copia (archivos normales), avisa con "copia" y sale con 0' {
        $t = Join-Path $TestDrive 'fallback'
        New-Target $t
        $entries = Get-ManagedEntries
        $entries.Count | Should -BeGreaterThan 5
        $r = Invoke-Link $t @() @{ CLAUDE_SETUP_NO_SYMLINK = '1' }
        $r.ExitCode | Should -Be 0 -Because ($r.Stdout + $r.Stderr)
        $r.Stdout | Should -Match 'AVISO.*copia'
        foreach ($e in $entries) {
            $p = Join-Path $t $e
            Test-Path -LiteralPath $p | Should -BeTrue -Because $e
            Test-IsReparse $p | Should -BeFalse -Because $e
        }
        foreach ($f in (Get-ManagedFiles)) {
            Get-FileHashValue (Join-Path $t $f) | Should -Be (Get-FileHashValue (Join-Path $script:src $f)) -Because $f
        }
    }

    It 'por defecto enlaza cada entrada gestionada al repo y reinstalar no crea backup (requiere symlinks: se omite si no se pueden crear sin admin)' -Skip:(-not $script:canSymlink) {
        $t = Join-Path $TestDrive 'links'
        New-Target $t
        $entries = Get-ManagedEntries
        $entries.Count | Should -BeGreaterThan 5
        $r = Invoke-Link $t
        $r.ExitCode | Should -Be 0 -Because ($r.Stdout + $r.Stderr)
        foreach ($e in $entries) {
            $item = Get-Item -LiteralPath (Join-Path $t $e) -Force
            $item.LinkType | Should -Be 'SymbolicLink' -Because $e
            $target = @($item.Target)[0]
            [System.IO.Path]::GetFullPath($target).TrimEnd('\') | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $script:src $e)).TrimEnd('\')) -Because $e
        }
        @(Get-BackupDirs $t).Count | Should -Be 0
        $r2 = Invoke-Link $t
        $r2.ExitCode | Should -Be 0 -Because ($r2.Stdout + $r2.Stderr)
        $r2.Stdout | Should -Match 'Sin cambios'
        $r2.Stdout | Should -Not -Match 'Enlazar:'
        $r2.Stdout | Should -Not -Match 'Backup:'
        @(Get-BackupDirs $t).Count | Should -Be 0
    }

    It '-Uninstall tras instalar sobre un CLAUDE.md con marcador restaura el marcador, quita lo gestionado y no toca lo ajeno' {
        $t = Join-Path $TestDrive 'uninst'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'MARCADOR-PREVIO'
        $others = '.credentials.json', 'history.jsonl', 'projects\p.txt', 'sessions\s.json', 'skills\gstack\SKILL.md', 'agents\mine.md'
        $before = @{}
        foreach ($o in $others) { $before[$o] = Get-FileHashValue (Join-Path $t $o) }
        $markerHash = Get-FileHashValue (Join-Path $t 'CLAUDE.md')
        $entries = Get-ManagedEntries
        $r = Invoke-Link $t @() @{ CLAUDE_SETUP_NO_SYMLINK = '1' }
        $r.ExitCode | Should -Be 0 -Because ($r.Stdout + $r.Stderr)
        (Get-BackupDirs $t).Count | Should -Be 1
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Test-Path -LiteralPath (Join-Path $t 'CLAUDE.md') | Should -BeTrue
        Get-FileHashValue (Join-Path $t 'CLAUDE.md') | Should -Be $markerHash
        foreach ($e in @($entries | Where-Object { $_ -ne 'CLAUDE.md' })) {
            Test-Path -LiteralPath (Join-Path $t $e) | Should -BeFalse -Because $e
        }
        foreach ($o in $others) {
            Get-FileHashValue (Join-Path $t $o) | Should -Be $before[$o] -Because $o
        }
    }

    It '-Uninstall con symlinks no borra nada dentro del repo (requiere symlinks: se omite si no se pueden crear sin admin)' -Skip:(-not $script:canSymlink) {
        $t = Join-Path $TestDrive 'uninst-links'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'MARCADOR-PREVIO'
        $snap = Get-TreeHash $script:src
        $snap.Length | Should -BeGreaterThan 0
        $r = Invoke-Link $t
        $r.ExitCode | Should -Be 0 -Because ($r.Stdout + $r.Stderr)
        Test-IsReparse (Join-Path $t 'CLAUDE.md') | Should -BeTrue
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Get-TreeHash $script:src | Should -Be $snap
        foreach ($e in @(Get-ManagedEntries | Where-Object { $_ -ne 'CLAUDE.md' })) {
            Test-Path -LiteralPath (Join-Path $t $e) | Should -BeFalse -Because $e
        }
        Get-Content -LiteralPath (Join-Path $t 'CLAUDE.md') | Should -Be 'MARCADOR-PREVIO'
        Test-Path -LiteralPath (Join-Path $script:src 'CLAUDE.md') | Should -BeTrue
    }

    It '-Uninstall quita junctions de carpetas sin borrar el contenido al que apuntan' {
        $t = Join-Path $TestDrive 'uninst-junction'
        New-Target $t
        $store = Join-Path $TestDrive 'junction-store'
        New-Item -ItemType Directory -Force -Path $store | Out-Null
        $skills = @(Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory)
        $skills.Count | Should -BeGreaterThan 0
        foreach ($s in $skills) {
            Copy-Item -LiteralPath $s.FullName -Destination (Join-Path $store $s.Name) -Recurse
            New-Item -ItemType Junction -Path (Join-Path $t "skills\$($s.Name)") -Value (Join-Path $store $s.Name) | Out-Null
        }
        $storeHash = Get-TreeHash $store
        $storeHash.Length | Should -BeGreaterThan 0
        New-FakeBackup $t | Out-Null
        foreach ($s in $skills) { Test-IsReparse (Join-Path $t "skills\$($s.Name)") | Should -BeTrue }
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        foreach ($s in $skills) {
            Test-Path -LiteralPath (Join-Path $t "skills\$($s.Name)") | Should -BeFalse -Because $s.Name
            Test-Path -LiteralPath (Join-Path $store $s.Name) | Should -BeTrue -Because $s.Name
        }
        Get-TreeHash $store | Should -Be $storeHash
        Get-Content -LiteralPath (Join-Path $t 'CLAUDE.md') | Should -Be 'MARCADOR-PREVIO'
        Test-Path -LiteralPath (Join-Path $t 'skills\gstack\SKILL.md') | Should -BeTrue
    }

    It '-Uninstall sin carpeta de backups falla con exit != 0 y no borra nada' {
        $t = Join-Path $TestDrive 'uninst-nobk'
        New-Target $t
        $r0 = Invoke-Link $t @() @{ CLAUDE_SETUP_NO_SYMLINK = '1' }
        $r0.ExitCode | Should -Be 0 -Because ($r0.Stdout + $r0.Stderr)
        @(Get-BackupDirs $t).Count | Should -Be 0
        $before = Get-TreeHash $t
        $before.Length | Should -BeGreaterThan 0
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Not -Be 0
        $u.Stdout | Should -Match 'backup'
        Get-TreeHash $t | Should -Be $before
    }

    It '-Uninstall -DryRun no cambia nada' {
        $t = Join-Path $TestDrive 'uninst-dry'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'MARCADOR-PREVIO'
        (Invoke-Link $t @() @{ CLAUDE_SETUP_NO_SYMLINK = '1' }).ExitCode | Should -Be 0
        $before = Get-TreeHash $t
        $before.Length | Should -BeGreaterThan 0
        $u = Invoke-Link $t @('-Uninstall', '-DryRun')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        $u.Stdout | Should -Match '\[DryRun\]'
        Get-TreeHash $t | Should -Be $before
    }

    It '-Uninstall tras reinstalar sobre copias editadas restaura los ORIGINALES (backup mas antiguo) y conserva los backups' {
        $t = Join-Path $TestDrive 'uninst-reinstall'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL-CLAUDE'
        Set-Content -LiteralPath (Join-Path $t 'settings.json') -Value '{"original":true}'
        $origClaude = Get-FileHashValue (Join-Path $t 'CLAUDE.md')
        $origSettings = Get-FileHashValue (Join-Path $t 'settings.json')
        $agent = @(Get-ChildItem -LiteralPath (Join-Path $script:src 'agents') -File)[0].Name
        $agent | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $t "agents\$agent") | Should -BeFalse
        $r1 = Invoke-Install $t
        $r1.ExitCode | Should -Be 0 -Because $r1.Stdout
        # Simula una actualizacion del repo: las copias instaladas cambian y se reinstala.
        Add-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'version antigua del repo'
        Add-Content -LiteralPath (Join-Path $t 'settings.json') -Value ' '
        $r2 = Invoke-Install $t
        $r2.ExitCode | Should -Be 0 -Because $r2.Stdout
        $setupDirs = @(Get-BackupDirs $t | Where-Object { $_.Name -like 'setup-*' } | ForEach-Object { $_.Name })
        $setupDirs.Count | Should -Be 2
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Get-FileHashValue (Join-Path $t 'CLAUDE.md') | Should -Be $origClaude
        Get-FileHashValue (Join-Path $t 'settings.json') | Should -Be $origSettings
        Test-Path -LiteralPath (Join-Path $t "agents\$agent") | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $t 'agents\mine.md') | Should -BeTrue
        # Los backups se conservan, marcados como consumidos.
        foreach ($n in $setupDirs) {
            Test-Path -LiteralPath (Join-Path $t "backups\restored-$n") | Should -BeTrue -Because $n
        }
    }

    It '-Uninstall guarda en backups\pre-uninstall-* lo editado tras instalar y no guarda lo identico al repo' {
        $t = Join-Path $TestDrive 'uninst-pre'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL-CLAUDE'
        $origClaude = Get-FileHashValue (Join-Path $t 'CLAUDE.md')
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        Add-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'memoria # del usuario'
        $editHash = Get-FileHashValue (Join-Path $t 'CLAUDE.md')
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Get-FileHashValue (Join-Path $t 'CLAUDE.md') | Should -Be $origClaude
        $pre = @(Get-BackupDirs $t | Where-Object { $_.Name -match '^pre-uninstall-\d{8}-\d{6}(-\d+)?$' })
        $pre.Count | Should -Be 1
        $saved = Join-Path $pre[0].FullName 'CLAUDE.md'
        Test-Path -LiteralPath $saved | Should -BeTrue
        Get-FileHashValue $saved | Should -Be $editHash
        Test-Path -LiteralPath (Join-Path $pre[0].FullName 'settings.json') | Should -BeFalse
        $savedFiles = @(Get-ChildItem -LiteralPath $pre[0].FullName -Recurse -File)
        $savedFiles.Count | Should -Be 1
    }

    It '-Uninstall sin ediciones posteriores no crea carpeta pre-uninstall' {
        $t = Join-Path $TestDrive 'uninst-nopre'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL-CLAUDE'
        (Invoke-Install $t).ExitCode | Should -Be 0
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        $names = @(Get-BackupDirs $t | ForEach-Object { $_.Name })
        $names.Count | Should -Be 1
        $names[0] | Should -Match '^restored-setup-'
    }

    It '-Uninstall -DryRun tras reinstalar con ediciones no cambia nada' {
        $t = Join-Path $TestDrive 'uninst-dry2'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL-CLAUDE'
        (Invoke-Install $t).ExitCode | Should -Be 0
        Add-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'version antigua del repo'
        (Invoke-Install $t).ExitCode | Should -Be 0
        Add-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'edicion del usuario'
        $before = Get-TreeHash $t
        $before.Length | Should -BeGreaterThan 0
        $u = Invoke-Link $t @('-Uninstall', '-DryRun')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        $u.Stdout | Should -Match '\[DryRun\].*pre-uninstall'
        Get-TreeHash $t | Should -Be $before
        @(Get-BackupDirs $t | Where-Object { $_.Name -like 'pre-uninstall-*' }).Count | Should -Be 0
    }

    It 'instalar sobre una junction del usuario la guarda como enlace en el backup y -Uninstall la recrea sin tocar su contenido' {
        $t = Join-Path $TestDrive 'user-junction'
        New-Target $t
        $skill = @(Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory)[0].Name
        $store = Join-Path $TestDrive 'user-junction-store'
        New-Item -ItemType Directory -Force -Path $store | Out-Null
        Set-Content -LiteralPath (Join-Path $store 'SKILL.md') -Value 'skill propia del usuario'
        Set-Content -LiteralPath (Join-Path $store 'notas.txt') -Value 'notas'
        $storeHash = Get-TreeHash $store
        $link = Join-Path $t "skills\$skill"
        New-Item -ItemType Junction -Path $link -Value $store | Out-Null
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        Test-IsReparse $link | Should -BeFalse
        $dirs = @(Get-BackupDirs $t)
        $dirs.Count | Should -Be 1
        $bkLink = Join-Path $dirs[0].FullName "skills\$skill"
        Test-IsReparse $bkLink | Should -BeTrue
        [System.IO.Path]::GetFullPath(@((Get-Item -LiteralPath $bkLink -Force).Target)[0]).TrimEnd('\') | Should -Be $store
        Get-TreeHash $store | Should -Be $storeHash
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Test-IsReparse $link | Should -BeTrue
        [System.IO.Path]::GetFullPath(@((Get-Item -LiteralPath $link -Force).Target)[0]).TrimEnd('\') | Should -Be $store
        Test-IsReparse (Join-Path $t "backups\restored-$($dirs[0].Name)\skills\$skill") | Should -BeTrue
        Get-TreeHash $store | Should -Be $storeHash
        Get-Content -LiteralPath (Join-Path $link 'notas.txt') | Should -Be 'notas'
    }

    It '(a) un segundo ciclo instalar/desinstalar restaura el estado previo a ESE ciclo y marca restored-setup-*' {
        $t = Join-Path $TestDrive 'cycle2'
        New-Target $t
        $claude = Join-Path $t 'CLAUDE.md'
        Set-Content -LiteralPath $claude -Value 'VERSION-A'
        $hashA = Get-FileHashValue $claude
        (Invoke-Install $t).ExitCode | Should -Be 0
        $first = @(Get-BackupDirs $t | Where-Object { $_.Name -like 'setup-*' } | ForEach-Object { $_.Name })
        $first.Count | Should -Be 1
        $u1 = Invoke-Link $t @('-Uninstall')
        $u1.ExitCode | Should -Be 0 -Because ($u1.Stdout + $u1.Stderr)
        Get-FileHashValue $claude | Should -Be $hashA
        Test-Path -LiteralPath (Join-Path $t "backups\restored-$($first[0])") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $t "backups\$($first[0])") | Should -BeFalse
        Set-Content -LiteralPath $claude -Value 'VERSION-B'
        $hashB = Get-FileHashValue $claude
        (Invoke-Install $t).ExitCode | Should -Be 0
        $u2 = Invoke-Link $t @('-Uninstall')
        $u2.ExitCode | Should -Be 0 -Because ($u2.Stdout + $u2.Stderr)
        Get-FileHashValue $claude | Should -Be $hashB
        @(Get-BackupDirs $t | Where-Object { $_.Name -match '^setup-' }).Count | Should -Be 0
        @(Get-BackupDirs $t | Where-Object { $_.Name -match '^restored-setup-' }).Count | Should -Be 2
    }

    It '(b) entradas del usuario identicas al repo se guardan al instalar y -Uninstall las restaura' {
        $t = Join-Path $TestDrive 'identical'
        New-Target $t
        $agents = @(Get-ChildItem -LiteralPath (Join-Path $script:src 'agents') -File)
        $agents.Count | Should -BeGreaterThan 1
        $mineAgent = "agents\$($agents[0].Name)"
        $otherAgent = "agents\$($agents[1].Name)"
        $skill = 'skills\' + @(Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory)[0].Name
        Copy-Item -LiteralPath (Join-Path $script:src 'CLAUDE.md') -Destination (Join-Path $t 'CLAUDE.md')
        Copy-Item -LiteralPath (Join-Path $script:src $mineAgent) -Destination (Join-Path $t $mineAgent)
        Copy-Item -LiteralPath (Join-Path $script:src $skill) -Destination (Join-Path $t $skill) -Recurse
        $own = @('CLAUDE.md', $mineAgent, "$skill\SKILL.md")
        $orig = @{}
        foreach ($o in $own) { $orig[$o] = Get-FileHashValue (Join-Path $t $o) }
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        foreach ($o in $own) { Get-FileHashValue (Join-Path $t $o) | Should -Be $orig[$o] -Because $o }
        $dirs = @(Get-BackupDirs $t)
        $dirs.Count | Should -Be 1
        foreach ($o in $own) {
            Get-FileHashValue (Join-Path $dirs[0].FullName $o) | Should -Be $orig[$o] -Because "backup de $o"
        }
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        foreach ($o in $own) {
            Test-Path -LiteralPath (Join-Path $t $o) | Should -BeTrue -Because $o
            Get-FileHashValue (Join-Path $t $o) | Should -Be $orig[$o] -Because $o
        }
        Test-Path -LiteralPath (Join-Path $t $otherAgent) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $t 'agents\mine.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $t 'skills\gstack\SKILL.md') | Should -BeTrue
    }

    It '(c) reinstalar lo ya instalado no crea backup ni cambia el manifiesto' {
        $t = Join-Path $TestDrive 'idem-manifest'
        New-Target $t
        Copy-Item -LiteralPath (Join-Path $script:src 'CLAUDE.md') -Destination (Join-Path $t 'CLAUDE.md')
        (Invoke-Install $t).ExitCode | Should -Be 0
        $dirs = @(Get-BackupDirs $t | ForEach-Object { $_.Name })
        $dirs.Count | Should -Be 1
        $mf = Join-Path $t 'backups\install-manifest.json'
        Test-Path -LiteralPath $mf | Should -BeTrue
        $m = Get-Content -Raw -LiteralPath $mf | ConvertFrom-Json
        $rec = @($m.entries | Where-Object { $_.path -eq 'CLAUDE.md' })
        $rec.Count | Should -Be 1
        $rec[0].backup | Should -Be $dirs[0]
        $agentRec = @($m.entries | Where-Object { $_.path -like 'agents\*' })
        $agentRec.Count | Should -BeGreaterThan 0
        foreach ($a in $agentRec) { $a.backup | Should -BeNullOrEmpty -Because $a.path }
        $mfHash = Get-FileHashValue $mf
        $tree = Get-TreeHash $t
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        $r.Stdout | Should -Not -Match 'Backup'
        @(Get-BackupDirs $t | ForEach-Object { $_.Name }) | Should -Be $dirs
        Get-FileHashValue $mf | Should -Be $mfHash
        Get-TreeHash $t | Should -Be $tree
    }

    It '(d) un segundo -Uninstall sale con 1 y no toca nada' {
        $t = Join-Path $TestDrive 'uninst-twice'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL'
        (Invoke-Install $t).ExitCode | Should -Be 0
        $u1 = Invoke-Link $t @('-Uninstall')
        $u1.ExitCode | Should -Be 0 -Because ($u1.Stdout + $u1.Stderr)
        $before = Get-TreeHash $t
        $before.Length | Should -BeGreaterThan 0
        $dirsBefore = @(Get-BackupDirs $t | ForEach-Object { $_.Name })
        $dirsBefore.Count | Should -BeGreaterThan 0
        $u2 = Invoke-Link $t @('-Uninstall')
        $u2.ExitCode | Should -Be 1
        $u2.Stdout | Should -Match 'backup'
        Get-TreeHash $t | Should -Be $before
        @(Get-BackupDirs $t | ForEach-Object { $_.Name }) | Should -Be $dirsBefore
    }

    It '(e) -Uninstall -DryRun tras instalar no renombra backups ni cambia el manifiesto' {
        $t = Join-Path $TestDrive 'uninst-dry3'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL'
        (Invoke-Install $t).ExitCode | Should -Be 0
        $mf = Join-Path $t 'backups\install-manifest.json'
        Test-Path -LiteralPath $mf | Should -BeTrue
        $mfHash = Get-FileHashValue $mf
        $before = Get-TreeHash $t
        $dirsBefore = @(Get-BackupDirs $t | ForEach-Object { $_.Name })
        $dirsBefore.Count | Should -Be 1
        $u = Invoke-Link $t @('-Uninstall', '-DryRun')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Get-TreeHash $t | Should -Be $before
        Get-FileHashValue $mf | Should -Be $mfHash
        @(Get-BackupDirs $t | ForEach-Object { $_.Name }) | Should -Be $dirsBefore
        @(Get-BackupDirs $t | Where-Object { $_.Name -like 'restored-*' }).Count | Should -Be 0
    }

    It '(f) una instalacion de la version anterior (setup-* sin manifiesto) se desinstala con el backup mas antiguo' {
        $t = Join-Path $TestDrive 'legacy'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL-LEGACY'
        $hash = Get-FileHashValue (Join-Path $t 'CLAUDE.md')
        $agent = 'agents\' + @(Get-ChildItem -LiteralPath (Join-Path $script:src 'agents') -File)[0].Name
        (Invoke-Install $t).ExitCode | Should -Be 0
        Remove-Item -LiteralPath (Join-Path $t 'backups\install-manifest.json')
        Test-Path -LiteralPath (Join-Path $t $agent) | Should -BeTrue
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Get-FileHashValue (Join-Path $t 'CLAUDE.md') | Should -Be $hash
        Test-Path -LiteralPath (Join-Path $t $agent) | Should -BeFalse
        @(Get-BackupDirs $t | Where-Object { $_.Name -match '^restored-setup-' }).Count | Should -Be 1
    }

    It '(g) si falta el backup de una entrada, -Uninstall sale con 1 sin tocar nada ni marcar backups' {
        $t = Join-Path $TestDrive 'uninst-fail'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL-CLAUDE'
        Set-Content -LiteralPath (Join-Path $t 'settings.json') -Value '{"original":true}'
        (Invoke-Install $t).ExitCode | Should -Be 0
        Add-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'edicion del usuario'
        $dirs = @(Get-BackupDirs $t)
        $dirs.Count | Should -Be 1
        Remove-Item -LiteralPath (Join-Path $dirs[0].FullName 'settings.json')
        $before = Get-TreeHash $t
        $before.Length | Should -BeGreaterThan 0
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 1
        $u.Stdout | Should -Match 'ERROR: settings\.json'
        Get-TreeHash $t | Should -Be $before
        @(Get-BackupDirs $t | Where-Object { $_.Name -like 'restored-*' }).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $t 'backups\install-manifest.json') | Should -BeTrue
    }

    It 'una junction rota del usuario se guarda al instalar y -Uninstall la recrea o informa sin perder datos' {
        $t = Join-Path $TestDrive 'broken-junction'
        New-Target $t
        $skill = @(Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory)[0].Name
        $gone = Join-Path $TestDrive 'broken-junction-gone'
        New-Item -ItemType Directory -Force -Path $gone | Out-Null
        $link = Join-Path $t "skills\$skill"
        New-Item -ItemType Junction -Path $link -Value $gone | Out-Null
        Remove-Item -LiteralPath $gone -Recurse -Force
        Test-IsReparse $link | Should -BeTrue
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'ORIGINAL'
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        $dirs = @(Get-BackupDirs $t)
        $dirs.Count | Should -Be 1
        $bkLink = Join-Path $dirs[0].FullName "skills\$skill"
        Test-IsReparse $bkLink | Should -BeTrue
        $u = Invoke-Link $t @('-Uninstall')
        if ($u.ExitCode -eq 0) {
            Test-IsReparse $link | Should -BeTrue
            [System.IO.Path]::GetFullPath(@((Get-Item -LiteralPath $link -Force).Target)[0]).TrimEnd('\') | Should -Be $gone
        }
        else {
            $u.Stdout | Should -Match ([regex]::Escape("ERROR: skills\$skill"))
            Test-IsReparse $bkLink | Should -BeTrue
        }
        Get-Content -LiteralPath (Join-Path $t 'CLAUDE.md') | Should -Be 'ORIGINAL'
    }

    It 'modo enlace sobre copias identicas del repo las quita sin crear backup nuevo (seam sin symlinks)' {
        $t = Join-Path $TestDrive 'seam'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'MARCADOR-PREVIO'
        $r0 = Invoke-Link $t @() @{ CLAUDE_SETUP_NO_SYMLINK = '1' }
        $r0.ExitCode | Should -Be 0 -Because ($r0.Stdout + $r0.Stderr)
        $names = @(Get-BackupDirs $t | ForEach-Object { $_.Name })
        $names.Count | Should -Be 1
        # Fuerza el modo enlace: en maquinas sin privilegios la creacion falla (exit 1), pero la decision
        # "copia identica -> borrar sin backup" ya se ha tomado y es lo que se comprueba.
        $r = Invoke-Link $t @() @{ CLAUDE_SETUP_FORCE_LINKS = '1' }
        $r.Stdout | Should -Match 'Quitar copia identica'
        $r.Stdout | Should -Not -Match 'Backup:'
        @(Get-BackupDirs $t | ForEach-Object { $_.Name }) | Should -Be $names
        $bkDir = @(Get-BackupDirs $t)[0].FullName
        $bkMarker = Join-Path $bkDir 'CLAUDE.md'
        Get-Content -LiteralPath $bkMarker | Should -Be 'MARCADOR-PREVIO'
    }

    It 'secuencia fallback -> modo enlace -> -Uninstall restaura el marcador original (requiere symlinks: se omite si no se pueden crear sin admin)' -Skip:(-not $script:canSymlink) {
        $t = Join-Path $TestDrive 'seq'
        New-Target $t
        Set-Content -LiteralPath (Join-Path $t 'CLAUDE.md') -Value 'MARCADOR-PREVIO'
        $r0 = Invoke-Link $t @() @{ CLAUDE_SETUP_NO_SYMLINK = '1' }
        $r0.ExitCode | Should -Be 0 -Because ($r0.Stdout + $r0.Stderr)
        $names = @(Get-BackupDirs $t | ForEach-Object { $_.Name })
        $names.Count | Should -Be 1
        $r = Invoke-Link $t
        $r.ExitCode | Should -Be 0 -Because ($r.Stdout + $r.Stderr)
        Test-IsReparse (Join-Path $t 'CLAUDE.md') | Should -BeTrue
        @(Get-BackupDirs $t | ForEach-Object { $_.Name }) | Should -Be $names
        $u = Invoke-Link $t @('-Uninstall')
        $u.ExitCode | Should -Be 0 -Because ($u.Stdout + $u.Stderr)
        Test-IsReparse (Join-Path $t 'CLAUDE.md') | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $t 'CLAUDE.md') | Should -Be 'MARCADOR-PREVIO'
    }

    It 'aborta con exit != 0 si TargetDir\skills es una junction y no toca el contenido al que apunta' {
        $t = Join-Path $TestDrive 'guard'
        New-Target $t
        Remove-Item -LiteralPath (Join-Path $t 'skills') -Recurse -Force
        $store = Join-Path $TestDrive 'guard-store'
        New-Item -ItemType Directory -Force -Path $store | Out-Null
        Set-Content -LiteralPath (Join-Path $store 'a.txt') -Value 'dato'
        New-Item -ItemType Junction -Path (Join-Path $t 'skills') -Value $store | Out-Null
        $hash = Get-TreeHash $store
        $hash.Length | Should -BeGreaterThan 0
        foreach ($mode in @(@('-Copy'), @(), @('-Uninstall'))) {
            $r = Invoke-Link $t $mode
            $r.ExitCode | Should -Not -Be 0 -Because ($mode -join ' ')
            $r.Stdout | Should -Match 'enlace'
            Get-TreeHash $store | Should -Be $hash
        }
        Test-Path -LiteralPath (Join-Path $t 'backups') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $t 'CLAUDE.md') | Should -BeFalse
    }

    It 'la sonda de symlinks no deja restos en TargetDir con -DryRun' {
        $t = Join-Path $TestDrive 'probe-dry'
        New-Target $t
        $before = @(Get-ChildItem -LiteralPath $t -Force | ForEach-Object { $_.Name }) | Sort-Object
        $r = Invoke-Link $t @('-DryRun')
        $r.ExitCode | Should -Be 0 -Because ($r.Stdout + $r.Stderr)
        @(Get-ChildItem -LiteralPath $t -Force | ForEach-Object { $_.Name }) | Sort-Object | Should -Be $before
        Test-Path -LiteralPath (Join-Path $TestDrive 'probe-new') | Should -BeFalse
        $r2 = Invoke-Link (Join-Path $TestDrive 'probe-new\sub') @('-DryRun')
        $r2.ExitCode | Should -Be 0 -Because ($r2.Stdout + $r2.Stderr)
        Test-Path -LiteralPath (Join-Path $TestDrive 'probe-new') | Should -BeFalse
    }
}
