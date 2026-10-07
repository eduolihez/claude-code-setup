BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $script:names = @('python-automation', 'soc-detection', 'hackathon', 'web')
    $script:tplCases = @($script:names | ForEach-Object { @{ Name = $_; Path = (Join-Path $root "templates\$_.md") } })
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    function Get-Tpl([string]$Name) {
        [IO.File]::ReadAllText((Join-Path $script:repoRoot "templates\$Name.md"), [Text.Encoding]::UTF8)
    }
    $o = [string][char]0xF3
    $script:defHecho = "Definici${o}n de hecho"
    $script:headings = @('## Contexto', '## Comandos', '## Convenciones', '## Seguridad', "## $script:defHecho")
    $script:noSecretos = "Nunca escribas secretos en c${o}digo ni en commits"
}

Describe 'Templates por tipo de proyecto' {
    It 'la lista de templates no esta vacia' {
        $dir = Join-Path $script:repoRoot 'templates'
        @(Get-ChildItem -Path $dir -Filter '*.md' -File -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }
    It '<Name>: existe' -ForEach $script:tplCases {
        $Path | Should -Exist
    }
    It '<Name>: tiene los 5 encabezados en orden' -ForEach $script:tplCases {
        $text = Get-Tpl $Name
        $last = -1
        foreach ($h in $script:headings) {
            $m = [regex]::Match($text, '(?m)^' + [regex]::Escape($h) + '\s*$')
            $m.Success | Should -BeTrue -Because "falta $h"
            $m.Index | Should -BeGreaterThan $last -Because "$h fuera de orden"
            $last = $m.Index
        }
    }
    It '<Name>: la seccion Seguridad prohibe secretos en codigo y commits' -ForEach $script:tplCases {
        $text = Get-Tpl $Name
        $sec = [regex]::Match($text, ('(?s)## Seguridad(.*?)## ' + $script:defHecho)).Groups[1].Value
        $sec.Contains($script:noSecretos) | Should -BeTrue
    }
    It '<Name>: contiene el marcador completar (stack pendiente)' -ForEach @(
        @{ Name = 'web' }
        @{ Name = 'hackathon' }
    ) {
        (Get-Tpl $Name).Contains('<!-- completar -->') | Should -BeTrue
    }
    It '<Name>: no contiene el marcador completar' -ForEach @(
        @{ Name = 'python-automation' }
        @{ Name = 'soc-detection' }
    ) {
        (Get-Tpl $Name).Contains('<!-- completar -->') | Should -BeFalse
    }
    It 'python-automation menciona <Needle>' -ForEach @(
        @{ Needle = 'ruff' }
        @{ Needle = 'pytest' }
    ) {
        (Get-Tpl 'python-automation') | Should -Match $Needle
    }
    It 'soc-detection menciona <Needle>' -ForEach @(
        @{ Needle = 'MITRE ATT&CK' }
        @{ Needle = 'Sigma' }
        @{ Needle = 'sanitiz' }
    ) {
        (Get-Tpl 'soc-detection') | Should -Match ([regex]::Escape($Needle))
    }
}
