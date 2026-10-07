@{
    ExcludeRules = @(
        # install.ps1 y el runner son scripts de consola interactivos: Write-Host es salida de usuario.
        'PSAvoidUsingWriteHost',
        # Cmdlets nativos con 1-2 argumentos obvios (Join-Path, Split-Path); nombrarlos no aporta claridad.
        'PSAvoidUsingPositionalParameters',
        # Los catch vacios son intencionales en limpieza best-effort (borrado de temporales, symlinks).
        'PSAvoidUsingEmptyCatchBlock',
        # Funciones auxiliares internas (plural descriptivo); no son cmdlets publicos.
        'PSUseSingularNouns',
        # Funciones internas de script; ya existe -DryRun propio y no se exponen como cmdlets.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
