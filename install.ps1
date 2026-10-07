[CmdletBinding()]
param(
    [string]$TargetDir = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$Copy,
    [switch]$DryRun
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

if (-not (Test-Path -LiteralPath $TargetDir)) {
    Write-Host "${prefix}Crear directorio destino $TargetDir"
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null }
}

foreach ($e in $entries) {
    $src = Join-Path $repoClaude $e.Rel
    $dst = Join-Path $TargetDir $e.Rel
    try {
        if (Test-SameAsRepo $e $src $dst) {
            Write-Host "${prefix}Sin cambios: $($e.Rel)"
            continue
        }
        if (Test-Path -LiteralPath $dst) {
            $bk = Join-Path (Get-BackupDir) $e.Rel
            Write-Host "${prefix}Backup: $($e.Rel) -> $bk"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bk) | Out-Null
                Move-Item -LiteralPath $dst -Destination $bk
            }
        }
        Write-Host "${prefix}Copiar: $($e.Rel)"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
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
        if (-not $e.IsDir) {
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
