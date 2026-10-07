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

$script:backupDir = $null
function Get-BackupDir {
    if ($null -eq $script:backupDir) {
        $base = Join-Path $TargetDir ('backups\setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
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
        $script:backupDir = $cand
    }
    return $script:backupDir
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
    # Se valida antes de tocar nada: sin backups no se desinstala.
    $bkRoot = Join-Path $TargetDir 'backups'
    $bks = @()
    if (Test-Path -LiteralPath $bkRoot -PathType Container) {
        $bks = @(Get-ChildItem -LiteralPath $bkRoot -Directory | Where-Object { $_.Name -match '^setup-\d{8}-\d{6}(-\d+)?$' })
    }
    if ($bks.Count -eq 0) {
        Write-Host "ERROR: no hay carpetas de backup en $bkRoot; no se puede desinstalar. No se borro nada."
        exit 1
    }
    $latest = $bks | Sort-Object @{ Expression = { $_.Name.Substring(0, 21) } }, @{ Expression = { if ($_.Name.Length -gt 21) { [int]$_.Name.Substring(22) } else { 0 } } } | Select-Object -Last 1
    Write-Host "${prefix}Restaurando desde el backup mas reciente: $($latest.FullName)"
    $restored = @{}
    foreach ($e in $entries) {
        $dst = Join-Path $TargetDir $e.Rel
        $bk = Join-Path $latest.FullName $e.Rel
        try {
            if (Test-Reparse $dst) {
                Write-Host "${prefix}Quitar enlace: $($e.Rel)"
                if (-not $DryRun) { Remove-Link $dst }
            }
            elseif (Test-Path -LiteralPath $dst) {
                Write-Host "${prefix}Quitar: $($e.Rel)"
                if (-not $DryRun) { Remove-Item -LiteralPath $dst -Recurse -Force }
            }
            if (Test-Path -LiteralPath $bk) {
                $restored[$e.Rel] = $true
                Write-Host "${prefix}Restaurar: $($e.Rel)"
                if (-not $DryRun) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
                    Copy-Item -LiteralPath $bk -Destination $dst -Recurse -Force
                }
            }
        }
        catch {
            Write-Host "ERROR: $($e.Rel): $($_.Exception.Message)"
            $failed++
        }
    }
    if (-not $DryRun) {
        foreach ($e in $entries) {
            $dst = Join-Path $TargetDir $e.Rel
            $present = (Test-Path -LiteralPath $dst) -or (Test-Reparse $dst)
            if ($present -ne [bool]$restored[$e.Rel]) {
                Write-Host "ERROR: verificacion de desinstalacion fallida: $($e.Rel)"
                $failed++
            }
        }
    }
    if ($DryRun) { Write-Host '[DryRun] Simulacion terminada, no se modifico nada.' }
    if ($failed -gt 0) {
        Write-Host "ERROR: $failed entradas con problemas."
        exit 1
    }
    if (-not $DryRun) { Write-Host 'Desinstalacion completada.' }
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

foreach ($e in $entries) {
    $src = Join-Path $repoClaude $e.Rel
    $dst = Join-Path $TargetDir $e.Rel
    try {
        if ($useLinks) { $same = Test-LinkedToRepo $src $dst }
        else { $same = Test-SameAsRepo $e $src $dst }
        if ($same) {
            Write-Host "${prefix}Sin cambios: $($e.Rel)"
            continue
        }
        if (Test-Reparse $dst) {
            # Un enlace no contiene datos: se quita sin tocar su destino.
            Write-Host "${prefix}Quitar enlace previo: $($e.Rel)"
            if (-not $DryRun) { Remove-Link $dst }
        }
        elseif ($useLinks -and (Test-SameAsRepo $e $src $dst)) {
            # Copia real identica al repo (p.ej. de una ejecucion previa en modo copia): es contenido del repo, sin backup.
            Write-Host "${prefix}Quitar copia identica: $($e.Rel)"
            if (-not $DryRun) { Remove-Item -LiteralPath $dst -Recurse -Force }
        }
        elseif (Test-Path -LiteralPath $dst) {
            $bk = Join-Path (Get-BackupDir) $e.Rel
            Write-Host "${prefix}Backup: $($e.Rel) -> $bk"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bk) | Out-Null
                Move-Item -LiteralPath $dst -Destination $bk
            }
        }
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
