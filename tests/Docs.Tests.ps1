BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $script:linkCases = @()
    $files = @(Get-ChildItem -Path $root -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\/](\.superpowers|node_modules|\.git)[\/]' })
    foreach ($f in $files) {
        $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        foreach ($m in [regex]::Matches($text, '\[[^\]]*\]\(([^)\s]+)\)')) {
            $t = $m.Groups[1].Value
            if ($t -match '^(https?:|mailto:|#)') { continue }
            $t = ($t -split '#')[0]
            if (-not $t) { continue }
            $rel = $f.FullName.Substring($root.Length + 1)
            $dest = [IO.Path]::GetFullPath((Join-Path $f.DirectoryName $t))
            $script:linkCases += @{ Source = $rel; Target = $t; Dest = $dest }
        }
    }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    function Get-Doc([string]$Rel) {
        [IO.File]::ReadAllText((Join-Path $script:repoRoot $Rel), [Text.Encoding]::UTF8)
    }
}

Describe 'Documentacion' {
    It 'hay al menos un enlace relativo en los .md (<Total>)' -ForEach @(@{ Total = $script:linkCases.Count }) {
        $Total | Should -BeGreaterThan 0
    }
    It 'enlace <Source> -> <Target> resuelve' -ForEach $script:linkCases {
        Test-Path -LiteralPath $Dest | Should -BeTrue
    }
    It 'README.md menciona install.ps1 y -DryRun' {
        $t = Get-Doc 'README.md'
        $t | Should -Match ([regex]::Escape('install.ps1'))
        $t | Should -Match ([regex]::Escape('-DryRun'))
    }
    It 'README.md enlaza el template <N>' -ForEach @(
        @{ N = 'python-automation' }, @{ N = 'soc-detection' }, @{ N = 'hackathon' }, @{ N = 'web' }
    ) {
        (Get-Doc 'README.md') | Should -Match ('\]\(templates/' + [regex]::Escape($N) + '\.md\)')
    }
    It 'docs/dependencies.md contiene obra/superpowers-marketplace' {
        (Get-Doc 'docs/dependencies.md') | Should -Match ([regex]::Escape('obra/superpowers-marketplace'))
    }
    It 'CHANGELOG.md contiene ## [0.1.0]' {
        (Get-Doc 'CHANGELOG.md') | Should -Match ([regex]::Escape('## [0.1.0]'))
    }
}
