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

Describe 'settings.json' {
    It 'es JSON valido' {
        { Get-Content -Raw -LiteralPath $script:settingsPath | ConvertFrom-Json } | Should -Not -Throw
    }
    It 'no contiene C:\Users ni <usuario>' {
        $text = Get-Content -Raw -LiteralPath $script:settingsPath
        $text | Should -Not -Match '(?i)C:[\\/]+Users'
        $text | Should -Not -Match '(?i)<usuario>'
    }
    It 'el patron de C:\Users detecta <Text> = <Expected>' -ForEach @(
        @{ Text = 'C:\Users\x';   Expected = $true }
        @{ Text = 'C:\\Users\\x'; Expected = $true }
        @{ Text = 'C:/otro';      Expected = $false }
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
}

Describe 'Contenido prohibido en claude/' {
    It 'no contiene <_>' -ForEach $script:forbidden {
        $name = $_
        $found = @(Get-ChildItem -Path (Join-Path $script:repoRoot 'claude') -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name })
        $found.Count | Should -Be 0
    }
}
