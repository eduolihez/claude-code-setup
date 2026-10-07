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
}
