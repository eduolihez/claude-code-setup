[CmdletBinding()]
param(
    [string]$TargetDir = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$Copy,
    [switch]$DryRun,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

$repoClaude = Join-Path $PSScriptRoot 'claude'
if (-not (Test-Path -LiteralPath $repoClaude -PathType Container)) {
    Write-Host "ERROR: no existe la carpeta de origen $repoClaude"
    exit 1
}
if (Test-Path -LiteralPath $TargetDir -PathType Leaf) {
    Write-Host "ERROR: TargetDir existe y es un archivo: $TargetDir"
    exit 1
}

# Entradas gestionadas (y solo estas): Rel = ruta relativa a claude/ y al destino.
$entries = @()
foreach ($n in 'CLAUDE.md', 'settings.json') {
    $entries += [pscustomobject]@{ Rel = $n; IsDir = $false }
}
foreach ($d in 'agents', 'hooks') {
    $p = Join-Path $repoClaude $d
    if (Test-Path -LiteralPath $p -PathType Container) {
        foreach ($f in Get-ChildItem -LiteralPath $p -File) {
            $entries += [pscustomobject]@{ Rel = "$d\$($f.Name)"; IsDir = $false }
        }
    }
}
$skillsRoot = Join-Path $repoClaude 'skills'
if (Test-Path -LiteralPath $skillsRoot -PathType Container) {
    foreach ($s in Get-ChildItem -LiteralPath $skillsRoot -Directory) {
        $entries += [pscustomobject]@{ Rel = "skills\$($s.Name)"; IsDir = $true }
    }
}

# Verdadero si la ruta es un reparse point (symlink o junction), incluso roto.
function Test-Reparse([string]$Path) {
    try { return (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) }
    catch { return $false }
}

# Quita un enlace SIN tocar el destino: nunca Remove-Item -Recurse sobre un reparse point.
function Remove-Link([string]$Path) {
    if (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::Directory) -ne 0) {
        [System.IO.Directory]::Delete($Path)
    }
    else {
        [System.IO.File]::Delete($Path)
    }
}

# Verdadero si $Dst es un enlace cuyo destino es exactamente $Src.
function Test-LinkedToRepo([string]$Src, [string]$Dst) {
    if (-not (Test-Reparse $Dst)) { return $false }
    try {
        $t = @((Get-Item -LiteralPath $Dst -Force).Target)
        if ($t.Count -eq 0 -or -not $t[0]) { return $false }
        $a = [System.IO.Path]::GetFullPath([string]$t[0]).TrimEnd('\')
        $b = [System.IO.Path]::GetFullPath($Src).TrimEnd('\')
        return ($a -ieq $b)
    }
    catch { return $false }
}

# Sondea si se pueden crear symlinks (archivo y carpeta) en el volumen de $BaseDir (se limpia siempre).
function Test-CanSymlink([string]$BaseDir) {
    if ($env:CLAUDE_SETUP_NO_SYMLINK -eq '1') { return $false }
    # Solo para tests: fuerza el modo enlace sin sondear (la creacion real puede fallar).
    if ($env:CLAUDE_SETUP_FORCE_LINKS -eq '1') { return $true }
    # Se usa el ancestro existente mas cercano para no crear TargetDir (ni en -DryRun).
    $root = $BaseDir
    while ($root -and -not (Test-Path -LiteralPath $root -PathType Container)) { $root = Split-Path -Parent $root }
    if (-not $root) { $root = [System.IO.Path]::GetTempPath() }
    $probe = Join-Path $root ('.claude-setup-probe-' + [guid]::NewGuid().ToString('N'))
    $ok = $false
    try {
        New-Item -ItemType Directory -Path $probe | Out-Null
        $f = Join-Path $probe 'f.txt'
        Set-Content -LiteralPath $f -Value 'x'
        $d = Join-Path $probe 'd'
        New-Item -ItemType Directory -Path $d | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $probe 'lf') -Value $f -ErrorAction Stop | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $probe 'ld') -Value $d -ErrorAction Stop | Out-Null
        $ok = $true
    }
    catch { $ok = $false }
    finally {
        foreach ($l in 'lf', 'ld') {
            $lp = Join-Path $probe $l
            if (Test-Reparse $lp) { try { Remove-Link $lp } catch { } }
        }
        Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $ok
}

function Get-RelFiles([string]$Root) {
    $prefix = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\') + '\'
    @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($prefix.Length) })
}

function Get-Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# Verdadero si el destino es identico al origen (para carpetas: mismos archivos y hashes, sin extras).
function Test-SameAsRepo($Entry, [string]$Src, [string]$Dst) {
    if (-not (Test-Path -LiteralPath $Dst)) { return $false }
    if (Test-Reparse $Dst) { return $false }
    if (-not $Entry.IsDir) {
        if (-not (Test-Path -LiteralPath $Dst -PathType Leaf)) { return $false }
        return ((Get-Hash $Src) -eq (Get-Hash $Dst))
    }
    if (-not (Test-Path -LiteralPath $Dst -PathType Container)) { return $false }
    $srcFiles = Get-RelFiles $Src
    $dstFiles = Get-RelFiles $Dst
    if ($srcFiles.Count -ne $dstFiles.Count) { return $false }
    foreach ($f in $srcFiles) {
        $d = Join-Path $Dst $f
        if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { return $false }
        if ((Get-Hash (Join-Path $Src $f)) -ne (Get-Hash $d)) { return $false }
    }
    return $true
}

# Mueve un enlace (el propio reparse point, no su destino). Solo dentro del mismo volumen:
# [IO.Directory]::Move / [IO.File]::Move renombran y fallan entre volumenes en vez de copiar contenido.
function Move-Link([string]$Path, [string]$Destination) {
    if (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::Directory) -ne 0) {
        [System.IO.Directory]::Move($Path, $Destination)
    }
    else {
        [System.IO.File]::Move($Path, $Destination)
    }
}

# Recrea en $Dst un enlace equivalente al enlace $Link (junction o symlink), sin tocar $Link.
function Copy-Link([string]$Link, [string]$Dst) {
    $item = Get-Item -LiteralPath $Link -Force
    $t = @($item.Target)
    if ($t.Count -eq 0 -or -not $t[0]) { throw "no se puede leer el destino del enlace $Link" }
    $type = 'SymbolicLink'
    if ($item.LinkType -eq 'Junction') { $type = 'Junction' }
    New-Item -ItemType $type -Path $Dst -Value ([string]$t[0]) -ErrorAction Stop | Out-Null
}

# Carpetas de backup reservadas en esta ejecucion, por tipo ('setup' o 'pre-uninstall').
$script:reservedDirs = @{}
function Get-BackupDir([string]$Kind = 'setup') {
    if (-not $script:reservedDirs.ContainsKey($Kind)) {
        $base = Join-Path $TargetDir ("backups\$Kind-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $cand = $base
        $i = 1
        if ($DryRun) {
            while (Test-Path -LiteralPath $cand) { $cand = "$base-$i"; $i++ }
        }
        else {
            # Reserva atomica: New-Item sin -Force falla si la carpeta ya existe.
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $base) | Out-Null
            while ($true) {
                try { New-Item -ItemType Directory -Path $cand | Out-Null; break }
                catch {
                    if (-not (Test-Path -LiteralPath $cand)) { throw }
                    $cand = "$base-$i"; $i++
                }
            }
        }
        $script:reservedDirs[$Kind] = $cand
    }
    return $script:reservedDirs[$Kind]
}

$bkRoot = Join-Path $TargetDir 'backups'
$manifestPath = Join-Path $bkRoot 'install-manifest.json'
$setupPattern = '^setup-\d{8}-\d{6}(-\d+)?$'

# Carpetas setup-* (candidatas a restaurar), de la mas antigua a la mas reciente (timestamp y luego -N).
function Get-SetupBackups {
    if (-not (Test-Path -LiteralPath $bkRoot -PathType Container)) { return @() }
    $bks = @(Get-ChildItem -LiteralPath $bkRoot -Directory | Where-Object { $_.Name -match $setupPattern })
    return @($bks | Sort-Object @{ Expression = { $_.Name.Substring(0, 21) } }, @{ Expression = { if ($_.Name.Length -gt 21) { [int]$_.Name.Substring(22) } else { 0 } } })
}

# Nombre de la carpeta setup-* mas antigua que contiene la entrada (o $null).
function Get-OldestContaining([object[]]$Sorted, [string]$Rel) {
    foreach ($b in $Sorted) {
        $cand = Join-Path $b.FullName $Rel
        if ((Test-Reparse $cand) -or (Test-Path -LiteralPath $cand)) { return $b.Name }
    }
    return $null
}

# Manifiesto del ciclo de instalacion actual: ruta gestionada -> carpeta setup-* con su original ($null si no existia).
# Devuelve $null si no hay manifiesto; lanza si es invalido (entrada externa: se valida).
function Read-Manifest {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }
    $m = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($null -eq $m -or $m.version -ne 1) { throw "manifiesto con formato desconocido: $manifestPath" }
    $valid = @{}
    foreach ($e in $entries) { $valid[$e.Rel] = $true }
    $records = @{}
    foreach ($r in @($m.entries)) {
        if ($null -eq $r) { continue }
        $p = [string]$r.path
        $b = $r.backup
        if (-not $valid.ContainsKey($p)) { continue }
        if ($null -ne $b -and ([string]$b -notmatch $setupPattern)) { throw "manifiesto: backup no valido para ${p}: $b" }
        $records[$p] = $b
    }
    return $records
}

function Save-Manifest([hashtable]$Records) {
    $list = @()
    foreach ($k in @($Records.Keys | Sort-Object)) {
        $list += [pscustomobject]@{ path = $k; backup = $Records[$k] }
    }
    $json = [pscustomobject]@{ version = 1; entries = $list } | ConvertTo-Json -Depth 4
    New-Item -ItemType Directory -Force -Path $bkRoot | Out-Null
    [System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

$prefix = ''
if ($DryRun) { $prefix = '[DryRun] ' }
$failed = 0

# Guard: si TargetDir o sus carpetas de primer nivel son enlaces, los destinos resolverian dentro del repo.
foreach ($g in @($TargetDir, (Join-Path $TargetDir 'skills'), (Join-Path $TargetDir 'agents'), (Join-Path $TargetDir 'hooks'))) {
    if (Test-Reparse $g) {
        Write-Host "ERROR: $g es un enlace (reparse point); abortado sin modificar nada."
        exit 1
    }
}

if ($Uninstall) {
    # Se valida antes de tocar nada: sin backups setup-* no se desinstala.
    $sorted = @(Get-SetupBackups)
    if ($sorted.Count -eq 0) {
        Write-Host "ERROR: no hay carpetas de backup setup-* en $bkRoot; no se puede desinstalar. No se borro nada."
        exit 1
    }
    try { $records = Read-Manifest }
    catch {
        Write-Host "ERROR: $($_.Exception.Message). No se borro nada."
        exit 1
    }
    if ($null -ne $records) {
        Write-Host "${prefix}Restaurando el estado previo a la instalacion actual segun $manifestPath"
    }
    else {
        # Instalacion de una version anterior sin manifiesto: backup setup-* mas antiguo que contiene cada entrada.
        Write-Host "${prefix}Sin manifiesto: restaurando cada entrada desde el backup mas antiguo que la contiene ($($sorted.Count) backups en $bkRoot)"
    }

    # Plan por entrada y validacion previa: si falta algun backup necesario no se toca nada.
    $plan = @()
    foreach ($e in $entries) {
        $bk = $null
        if ($null -ne $records) {
            if (-not $records.ContainsKey($e.Rel)) {
                Write-Host "${prefix}Omitir (no la instalo este instalador): $($e.Rel)"
                continue
            }
            if ($records[$e.Rel]) {
                $bk = Join-Path (Join-Path $bkRoot $records[$e.Rel]) $e.Rel
                if (-not ((Test-Reparse $bk) -or (Test-Path -LiteralPath $bk))) {
                    Write-Host "ERROR: $($e.Rel): falta su backup $bk"
                    $failed++
                }
            }
        }
        else {
            $name = Get-OldestContaining $sorted $e.Rel
            if ($name) { $bk = Join-Path (Join-Path $bkRoot $name) $e.Rel }
        }
        $plan += [pscustomobject]@{ Entry = $e; Backup = $bk }
    }
    if ($failed -gt 0) {
        Write-Host "ERROR: $failed backups necesarios no estan; no se borro nada."
        exit 1
    }

    foreach ($p in $plan) {
        $e = $p.Entry
        $bk = $p.Backup
        $src = Join-Path $repoClaude $e.Rel
        $dst = Join-Path $TargetDir $e.Rel
        try {
            if (Test-Reparse $dst) {
                Write-Host "${prefix}Quitar enlace: $($e.Rel)"
                if (-not $DryRun) { Remove-Link $dst }
            }
            elseif (Test-SameAsRepo $e $src $dst) {
                Write-Host "${prefix}Quitar: $($e.Rel)"
                if (-not $DryRun) { Remove-Item -LiteralPath $dst -Recurse -Force }
            }
            elseif (Test-Path -LiteralPath $dst) {
                # Difiere del repo (p.ej. memoria # en CLAUDE.md): se guarda, nunca se pierde.
                $keep = Join-Path (Get-BackupDir 'pre-uninstall') $e.Rel
                Write-Host "${prefix}Guardar cambios: $($e.Rel) -> $keep"
                if (-not $DryRun) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $keep) | Out-Null
                    Move-Item -LiteralPath $dst -Destination $keep
                }
            }
            if ($bk) {
                Write-Host "${prefix}Restaurar: $($e.Rel) <- $bk"
                if (-not $DryRun) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
                    if (Test-Reparse $bk) { Copy-Link $bk $dst }
                    else { Copy-Item -LiteralPath $bk -Destination $dst -Recurse -Force }
                }
            }
        }
        catch {
            Write-Host "ERROR: $($e.Rel): $($_.Exception.Message)"
            $failed++
        }
    }
    if (-not $DryRun) {
        foreach ($p in $plan) {
            $dst = Join-Path $TargetDir $p.Entry.Rel
            $present = (Test-Path -LiteralPath $dst) -or (Test-Reparse $dst)
            if ($present -ne [bool]$p.Backup) {
                Write-Host "ERROR: verificacion de desinstalacion fallida: $($p.Entry.Rel)"
                $failed++
            }
        }
    }
    if ($DryRun) { Write-Host '[DryRun] Simulacion terminada, no se modifico nada.' }
    if ($failed -gt 0) {
        Write-Host "ERROR: $failed entradas con problemas. No se marco ningun backup como restaurado."
        exit 1
    }
    if (-not $DryRun) {
        # Ciclo consumido: los backups setup-* pasan a restored-setup-* (nunca candidatos) y el manifiesto se archiva.
        try {
            foreach ($b in $sorted) {
                Write-Host "Marcar como restaurado: $($b.Name) -> restored-$($b.Name)"
                Rename-Item -LiteralPath $b.FullName -NewName ('restored-' + $b.Name)
            }
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                $arch = 'restored-install-manifest-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'
                $i = 1
                while (Test-Path -LiteralPath (Join-Path $bkRoot $arch)) {
                    $arch = 'restored-install-manifest-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$i.json"; $i++
                }
                Rename-Item -LiteralPath $manifestPath -NewName $arch
            }
        }
        catch {
            Write-Host "ERROR: no se pudieron marcar los backups como restaurados: $($_.Exception.Message)"
            exit 1
        }
        Write-Host 'Desinstalacion completada.'
    }
    exit 0
}

$useLinks = $false
if (-not $Copy) {
    if (Test-CanSymlink $TargetDir) { $useLinks = $true }
    else { Write-Host 'AVISO: no se pueden crear enlaces simbolicos (sin privilegios o CLAUDE_SETUP_NO_SYMLINK=1); se usa copia en esta ejecucion.' }
}

if (-not (Test-Path -LiteralPath $TargetDir)) {
    Write-Host "${prefix}Crear directorio destino $TargetDir"
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null }
}

# Manifiesto del ciclo actual. Una entrada registrada la puso este instalador (reinstalar no crea backup nuevo);
# una no registrada se adopta por primera vez y, si existe, se guarda en backup aunque sea identica al repo.
try { $records = Read-Manifest }
catch {
    Write-Host "ERROR: $($_.Exception.Message). No se modifico nada."
    exit 1
}
if ($null -eq $records) {
    $records = @{}
    # Instalacion previa sin manifiesto (version anterior): sus setup-* guardan los originales.
    $legacy = @(Get-SetupBackups)
    if ($legacy.Count -gt 0) {
        foreach ($e in $entries) {
            $name = Get-OldestContaining $legacy $e.Rel
            if ($name) { $records[$e.Rel] = $name }
        }
    }
}

foreach ($e in $entries) {
    $src = Join-Path $repoClaude $e.Rel
    $dst = Join-Path $TargetDir $e.Rel
    $owned = $records.ContainsKey($e.Rel)
    $bkName = $null
    try {
        if ($useLinks) { $same = Test-LinkedToRepo $src $dst }
        else { $same = (Test-SameAsRepo $e $src $dst) -and $owned }
        if ($same) {
            # En modo enlace, un enlace al repo siempre lo puso el instalador (no contiene datos).
            if (-not $owned) { $records[$e.Rel] = $null }
            Write-Host "${prefix}Sin cambios: $($e.Rel)"
            continue
        }
        if ((Test-Reparse $dst) -and (Test-LinkedToRepo $src $dst)) {
            # Enlace al repo de una instalacion previa: no es del usuario, se quita sin backup.
            Write-Host "${prefix}Quitar enlace previo: $($e.Rel)"
            if (-not $DryRun) { Remove-Link $dst }
        }
        elseif (Test-Reparse $dst) {
            # Enlace del usuario: se mueve el propio enlace al backup (mismo volumen), sin tocar su destino.
            $bkName = Split-Path -Leaf (Get-BackupDir)
            $bk = Join-Path (Get-BackupDir) $e.Rel
            Write-Host "${prefix}Backup de enlace: $($e.Rel) -> $bk"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bk) | Out-Null
                Move-Link $dst $bk
            }
        }
        elseif ($useLinks -and $owned -and (Test-SameAsRepo $e $src $dst)) {
            # Copia identica que puso este instalador (p.ej. una ejecucion previa en modo copia): sin backup.
            Write-Host "${prefix}Quitar copia identica: $($e.Rel)"
            if (-not $DryRun) { Remove-Item -LiteralPath $dst -Recurse -Force }
        }
        elseif (Test-Path -LiteralPath $dst) {
            $bkName = Split-Path -Leaf (Get-BackupDir)
            $bk = Join-Path (Get-BackupDir) $e.Rel
            Write-Host "${prefix}Backup: $($e.Rel) -> $bk"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bk) | Out-Null
                Move-Item -LiteralPath $dst -Destination $bk
            }
        }
        # Primera adopcion: se registra donde quedo el original ($null si no existia). Si ya estaba
        # registrada, el original del ciclo sigue en su carpeta y un backup nuevo solo guarda versiones posteriores.
        if (-not $owned) { $records[$e.Rel] = $bkName }
        if ($useLinks) {
            Write-Host "${prefix}Enlazar: $($e.Rel)"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
                New-Item -ItemType SymbolicLink -Path $dst -Value $src -ErrorAction Stop | Out-Null
            }
        }
        else {
            Write-Host "${prefix}Copiar: $($e.Rel)"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
                Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
            }
        }
    }
    catch {
        Write-Host "ERROR: $($e.Rel): $($_.Exception.Message)"
        $failed++
    }
}

if (-not $DryRun) {
    try { Save-Manifest $records }
    catch {
        Write-Host "ERROR: no se pudo escribir el manifiesto $($manifestPath): $($_.Exception.Message)"
        $failed++
    }
}

if ($DryRun) {
    Write-Host '[DryRun] Simulacion terminada, no se modifico nada.'
    if ($failed -gt 0) {
        Write-Host "ERROR: $failed entradas con problemas."
        exit 1
    }
    exit 0
}

Write-Host ''
Write-Host 'Verificacion:'
$ok = 0
foreach ($e in $entries) {
    $src = Join-Path $repoClaude $e.Rel
    $dst = Join-Path $TargetDir $e.Rel
    $good = $false
    try {
        if ($useLinks) {
            $good = (Test-LinkedToRepo $src $dst) -and (Test-Path -LiteralPath $dst)
        }
        elseif (-not $e.IsDir) {
            $good = (Test-Path -LiteralPath $dst -PathType Leaf) -and ((Get-Hash $src) -eq (Get-Hash $dst))
        }
        elseif (Test-Path -LiteralPath $dst -PathType Container) {
            $good = $true
            foreach ($f in Get-RelFiles $src) {
                $d = Join-Path $dst $f
                if (-not ((Test-Path -LiteralPath $d -PathType Leaf) -and ((Get-Hash (Join-Path $src $f)) -eq (Get-Hash $d)))) { $good = $false }
            }
        }
    }
    catch { $good = $false }
    if ($good) { $ok++; Write-Host "  OK     $($e.Rel)" }
    else { $failed++; Write-Host "  FALLO  $($e.Rel)" }
}
Write-Host "Resumen: $ok de $($entries.Count) entradas verificadas."
if ($failed -gt 0) {
    Write-Host "ERROR: $failed entradas con problemas."
    exit 1
}
exit 0
