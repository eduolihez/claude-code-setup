BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $script:agentFiles = @(Get-ChildItem -Path (Join-Path $root 'claude\agents') -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object { @{ Path = $_.FullName; Base = $_.BaseName } })
    $script:skillFiles = @(Get-ChildItem -Path (Join-Path $root 'claude\skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object { @{ Path = (Join-Path $_.FullName 'SKILL.md'); Dir = $_.Name } })
    $script:forbidden = @('.credentials.json', 'history.jsonl', 'projects', 'sessions', 'backups')
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\Get-Frontmatter.ps1')
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:settingsPath = Join-Path $script:repoRoot 'claude\settings.json'
}

Describe 'Agentes' {
    It 'existe al menos un agente' {
        @(Get-ChildItem -Path (Join-Path $script:repoRoot 'claude\agents') -Filter '*.md' -File -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }
    It '<Base>: name coincide con el archivo, description y tools no vacios' -ForEach $script:agentFiles {
        $fm = Get-Frontmatter -Path $Path
        $fm['name'] | Should -Be $Base
        [string]$fm['description'] | Should -Not -BeNullOrEmpty
        [string]$fm['tools'] | Should -Not -BeNullOrEmpty
    }
}

Describe 'Agentes SOC' {
    It '<Name>: existe y tools es exactamente Read, Grep, Glob' -ForEach @(
        @{ Name = 'alert-triage' }
        @{ Name = 'detection-engineer' }
    ) {
        $p = Join-Path $script:repoRoot "claude\agents\$Name.md"
        $p | Should -Exist
        $fm = Get-Frontmatter -Path $p
        [string]$fm['tools'] | Should -BeExactly 'Read, Grep, Glob'
    }
    It '<Name>: el cuerpo contiene <Needle>' -ForEach @(
        @{ Name = 'alert-triage';       Needle = 'sanitiz' }
        @{ Name = 'alert-triage';       Needle = 'Severidad' }
        @{ Name = 'detection-engineer'; Needle = 'Sigma' }
        @{ Name = 'detection-engineer'; Needle = 'YARA' }
        @{ Name = 'detection-engineer'; Needle = 'ATT&CK' }
    ) {
        $p = Join-Path $script:repoRoot "claude\agents\$Name.md"
        $p | Should -Exist
        $text = Get-Content -Raw -LiteralPath $p
        $text.Contains($Needle) | Should -BeTrue
    }
}

Describe 'Skills' {
    It 'existe al menos una skill' {
        @(Get-ChildItem -Path (Join-Path $script:repoRoot 'claude\skills') -Directory -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }
    It '<Dir>: name coincide con la carpeta y description no vacia' -ForEach $script:skillFiles {
        $fm = Get-Frontmatter -Path $Path
        $fm['name'] | Should -Be $Dir
        [string]$fm['description'] | Should -Not -BeNullOrEmpty
    }
}

Describe 'Skills hackathon-scaffold e ioc-defang' {
    BeforeAll {
        function Get-SkillBody([string]$Path) {
            $raw = Get-Content -Raw -LiteralPath $Path
            $m = [regex]::Match($raw, '(?s)\A---\r?\n.*?\r?\n---\r?\n(.*)\z')
            if (-not $m.Success) { throw "Sin frontmatter: $Path" }
            $m.Groups[1].Value
        }
        $script:hsPath = Join-Path $script:repoRoot 'claude\skills\hackathon-scaffold\SKILL.md'
        $script:iocPath = Join-Path $script:repoRoot 'claude\skills\ioc-defang\SKILL.md'
    }
    It '<Name>: existe' -ForEach @(
        @{ Name = 'hackathon-scaffold' }
        @{ Name = 'ioc-defang' }
    ) {
        (Join-Path $script:repoRoot "claude\skills\$Name\SKILL.md") | Should -Exist
    }
    It 'hackathon-scaffold tiene disable-model-invocation true' {
        $fm = Get-Frontmatter -Path $script:hsPath
        [string]$fm['disable-model-invocation'] | Should -BeExactly 'true'
    }
    It 'ioc-defang no desactiva la invocacion del modelo' {
        $fm = Get-Frontmatter -Path $script:iocPath
        $fm.Contains('disable-model-invocation') | Should -BeFalse
    }
    It 'cuerpo de hackathon-scaffold menciona <Needle>' -ForEach @(
        @{ Needle = 'MVP' }
        @{ Needle = 'README' }
        @{ Needle = 'checklist' }
    ) {
        $body = Get-SkillBody $script:hsPath
        $body.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) | Should -BeGreaterOrEqual 0
    }
    It 'cuerpo de ioc-defang contiene el ejemplo <Needle>' -ForEach @(
        @{ Needle = 'hxxps://example[.]com' }
        @{ Needle = '192[.]0[.]2[.]1' }
    ) {
        $body = Get-SkillBody $script:iocPath
        $body.Contains($Needle) | Should -BeTrue
    }
}

Describe 'settings.json' {
    It 'es JSON valido' {
        { Get-Content -Raw -LiteralPath $script:settingsPath | ConvertFrom-Json } | Should -Not -Throw
    }
    # Las cadenas con la ruta de perfil y el nombre de usuario se construyen por concatenacion
    # para que el propio archivo versionado no las contenga.
    It 'no contiene la ruta de perfil de usuario ni el nombre de usuario local' {
        $text = Get-Content -Raw -LiteralPath $script:settingsPath
        $text | Should -Not -Match '(?i)C:[\\/]+Users'
        $text | Should -Not -Match ('(?i)' + 'edu' + 'ol')
    }
    It 'el patron de la ruta de perfil detecta <Text> = <Expected>' -ForEach @(
        @{ Text = ('C:' + '\Users\x');     Expected = $true }
        @{ Text = ('C:' + '\\Users\\x');   Expected = $true }
        @{ Text = 'C:/otro';               Expected = $false }
    ) {
        ($Text -match '(?i)C:[\\/]+Users') | Should -Be $Expected
    }
    It 'todo command de hook contiene %USERPROFILE%' {
        $json = Get-Content -Raw -LiteralPath $script:settingsPath | ConvertFrom-Json
        $cmds = @()
        if ($json.PSObject.Properties['hooks']) {
            foreach ($evt in $json.hooks.PSObject.Properties) {
                foreach ($grp in @($evt.Value)) {
                    foreach ($h in @($grp.hooks)) {
                        if ($h.PSObject.Properties['command']) { $cmds += [string]$h.command }
                    }
                }
            }
        }
        $cmds.Count | Should -BeGreaterThan 0
        foreach ($c in $cmds) { $c | Should -Match '%USERPROFILE%' }
    }
    It 'hay un hook PreToolUse para Write y Edit que referencia block-secrets-write.ps1' {
        $json = Get-Content -Raw -LiteralPath $script:settingsPath | ConvertFrom-Json
        $matches2 = @()
        foreach ($grp in @($json.hooks.PreToolUse)) {
            $m = [string]$grp.matcher
            if ($m -match '\bWrite\b' -and $m -match '\bEdit\b') {
                foreach ($h in @($grp.hooks)) {
                    if ([string]$h.command -match 'block-secrets-write\.ps1') { $matches2 += $h }
                }
            }
        }
        $matches2.Count | Should -BeGreaterThan 0
    }
    It 'todo script de hook referenciado en settings.json existe en claude/hooks' {
        $json = Get-Content -Raw -LiteralPath $script:settingsPath | ConvertFrom-Json
        $cmds = @()
        foreach ($evt in $json.hooks.PSObject.Properties) {
            foreach ($grp in @($evt.Value)) {
                foreach ($h in @($grp.hooks)) { $cmds += [string]$h.command }
            }
        }
        if ($json.PSObject.Properties['statusLine']) { $cmds += [string]$json.statusLine.command }
        $names = @()
        foreach ($c in $cmds) {
            foreach ($m in [regex]::Matches($c, 'claude\\hooks\\([A-Za-z0-9._-]+\.ps1)')) { $names += $m.Groups[1].Value }
        }
        $names.Count | Should -BeGreaterThan 0
        foreach ($n in $names) {
            (Join-Path $script:repoRoot "claude\hooks\$n") | Should -Exist
        }
    }
}

Describe 'Contenido prohibido en claude/' {
    It 'no contiene <_>' -ForEach $script:forbidden {
        $name = $_
        $found = @(Get-ChildItem -Path (Join-Path $script:repoRoot 'claude') -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name })
        $found.Count | Should -Be 0
    }
}
