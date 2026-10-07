BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Ci = Join-Path $script:Root '.github/workflows/ci.yml'
    $script:Hook = Join-Path $script:Root '.githooks/pre-commit'
    $script:Settings = Join-Path $script:Root 'PSScriptAnalyzerSettings.psd1'
}

Describe 'workflow de CI' {
    It 'existe' {
        Test-Path -LiteralPath $script:Ci | Should -BeTrue
    }

    It 'contiene <_>' -ForEach @(
        'pull_request', 'push', 'gitleaks', 'Invoke-ScriptAnalyzer', 'Invoke-Tests.ps1',
        'windows-latest', 'permissions:',
        'npx markdownlint-cli2 "**/*.md" "#docs/superpowers" "#.superpowers" "#node_modules"'
    ) {
        (Get-Content -LiteralPath $script:Ci -Raw).Contains($_) | Should -BeTrue
    }
}

Describe 'pre-commit local' {
    It 'existe' {
        Test-Path -LiteralPath $script:Hook | Should -BeTrue
    }

    It 'empieza por shebang sh' {
        (Get-Content -LiteralPath $script:Hook -TotalCount 1) | Should -BeExactly '#!/bin/sh'
    }

    It 'ejecuta gitleaks protect --staged' {
        (Get-Content -LiteralPath $script:Hook -Raw).Contains('gitleaks protect --staged') | Should -BeTrue
    }

    It 'usa finales de linea LF' {
        (Get-Content -LiteralPath $script:Hook -Raw).Contains("`r") | Should -BeFalse
    }
}

Describe 'PSScriptAnalyzerSettings.psd1' {
    It 'se importa como hashtable' {
        (Import-PowerShellDataFile -LiteralPath $script:Settings) | Should -BeOfType [hashtable]
    }

    It 'cada exclusion lleva un comentario en la misma linea o la anterior' {
        $lines = @(Get-Content -LiteralPath $script:Settings)
        $data = Import-PowerShellDataFile -LiteralPath $script:Settings
        $rules = @($data.ExcludeRules)
        foreach ($rule in $rules) {
            $idx = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match ("^\s*'?" + [regex]::Escape($rule) + "'?\s*,?\s*(#.*)?$")) { $idx = $i; break }
            }
            $idx | Should -BeGreaterOrEqual 0 -Because "la regla $rule debe aparecer en una linea propia"
            $same = $lines[$idx] -match '#'
            $prev = ($idx -gt 0) -and ($lines[$idx - 1] -match '^\s*#')
            ($same -or $prev) | Should -BeTrue -Because "la regla $rule necesita comentario"
        }
    }
}
