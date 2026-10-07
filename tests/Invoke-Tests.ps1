$ErrorActionPreference = 'Stop'
$mod = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.5.0' } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $mod) {
    Write-Host 'Pester >= 5.5 no esta instalado. Ejecuta: Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck'
    exit 1
}
Import-Module $mod.Path -Force
$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0 -or $result.FailedBlocksCount -gt 0 -or $result.FailedContainersCount -gt 0) { exit 1 }
exit 0
