BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\Get-Frontmatter.ps1')
}

Describe 'Get-Frontmatter' {
    It 'lee name y description de un archivo valido' {
        $p = Join-Path $TestDrive 'ok.md'
        Set-Content -Path $p -Value "---`nname: foo`ndescription: bar baz`n---`ncuerpo"
        $fm = Get-Frontmatter -Path $p
        $fm['name'] | Should -Be 'foo'
        $fm['description'] | Should -Be 'bar baz'
    }
    It 'conserva el valor completo cuando contiene dos puntos' {
        $p = Join-Path $TestDrive 'colon.md'
        Set-Content -Path $p -Value "---`nname: foo`ndescription: a: b`n---`n"
        (Get-Frontmatter -Path $p)['description'] | Should -Be 'a: b'
    }
    It 'lanza si no hay delimitador de apertura' {
        $p = Join-Path $TestDrive 'noopen.md'
        Set-Content -Path $p -Value "name: foo`n---`n"
        { Get-Frontmatter -Path $p } | Should -Throw "Frontmatter ausente: $p"
    }
    It 'lanza si no hay delimitador de cierre' {
        $p = Join-Path $TestDrive 'noclose.md'
        Set-Content -Path $p -Value "---`nname: foo`n"
        { Get-Frontmatter -Path $p } | Should -Throw "Frontmatter ausente: $p"
    }
    It 'lee frontmatter con finales de linea CRLF' {
        $p = Join-Path $TestDrive 'crlf.md'
        [System.IO.File]::WriteAllText($p, "---`r`nname: foo`r`ndescription: bar`r`n---`r`ncuerpo`r`n")
        $fm = Get-Frontmatter -Path $p
        $fm['name'] | Should -Be 'foo'
        $fm['name'] | Should -Not -Match "`r"
        $fm['description'] | Should -Be 'bar'
    }
}
