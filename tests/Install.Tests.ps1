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

    It 'no crea backups si las skills del destino ya son identicas al repo' {
        $t = Join-Path $TestDrive 'skillsame'
        New-Target $t
        $skillsDst = Join-Path $t 'skills'
        foreach ($s in Get-ChildItem -LiteralPath (Join-Path $script:src 'skills') -Directory) {
            Copy-Item -LiteralPath $s.FullName -Destination (Join-Path $skillsDst $s.Name) -Recurse
        }
        $r = Invoke-Install $t
        $r.ExitCode | Should -Be 0 -Because $r.Stdout
        Test-Path -LiteralPath (Join-Path $t 'backups') | Should -BeFalse
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
        Test-Path -LiteralPath (Join-Path $t 'backups') | Should -BeFalse
        $r2 = Invoke-Link $t
        $r2.ExitCode | Should -Be 0 -Because ($r2.Stdout + $r2.Stderr)
        $r2.Stdout | Should -Match 'Sin cambios'
        $r2.Stdout | Should -Not -Match 'Enlazar:'
        $r2.Stdout | Should -Not -Match 'Backup:'
        Test-Path -LiteralPath (Join-Path $t 'backups') | Should -BeFalse
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
        Test-Path -LiteralPath (Join-Path $t 'backups') | Should -BeFalse
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
