BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers.ps1')
    $script:Root = Split-Path -Parent $PSScriptRoot
}

Describe 'gitignore allowlist' {
    It 'ignora <_>' -ForEach @(
        'claude/.credentials.json', 'claude/settings.local.json', 'claude/history.jsonl',
        'claude/projects/p/a.jsonl', 'claude/sessions/s.json', 'claude/backups/b',
        'claude/hooks/token.txt', '.env', '.superpowers/x',
        'docs/x.txt', 'scripts/x.psm1', 'claude/agents/x.json'
    ) {
        Test-GitIgnored -RepoRoot $script:Root -Path $_ | Should -BeTrue
    }

    It 'no ignora <_>' -ForEach @(
        'README.md', 'LICENSE', '.gitattributes', '.gitleaks.toml', 'install.ps1',
        'claude/CLAUDE.md', 'claude/settings.json', 'claude/agents/a.md', 'claude/hooks/a.ps1',
        'claude/skills/s/SKILL.md', 'templates/web.md', 'docs/roadmap.md', 'tests/X.Tests.ps1',
        'scripts/Get-Frontmatter.ps1', '.github/workflows/ci.yml', '.githooks/pre-commit',
        'plugin/README.md', 'PSScriptAnalyzerSettings.psd1', '.markdownlint.jsonc', '.markdownlint-cli2.jsonc'
    ) {
        Test-GitIgnored -RepoRoot $script:Root -Path $_ | Should -BeFalse
    }

    # La allowlist solo re-incluye claude/skills/*/SKILL.md: un archivo extra en una skill
    # quedaria ignorado en silencio. Este test lo hace fallar de forma visible.
    It 'no ignora ningun archivo presente bajo claude/skills' {
        $skills = Join-Path $script:Root 'claude\skills'
        $files = @(Get-ChildItem -LiteralPath $skills -Recurse -File)
        $files.Count | Should -BeGreaterThan 0
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($script:Root.TrimEnd('\').Length + 1).Replace('\', '/')
            Test-GitIgnored -RepoRoot $script:Root -Path $rel | Should -BeFalse -Because $rel
        }
    }
}
