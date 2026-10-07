# Linea de estado: stdin {"model":{"display_name":"..."},"workspace":{"current_dir":"..."}} -> "[modelo] carpeta".
# Ante entrada vacia o invalida imprime una linea minima "[claude]" y sale con 0, sin escribir en stderr.
$line = '[claude]'
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $data = $raw | ConvertFrom-Json
        $model = [string]$data.model.display_name
        $cwd = [string]$data.workspace.current_dir
        if ($model -and $cwd) {
            $line = "[$model] " + (Split-Path -Leaf $cwd)
        }
    }
}
catch {
    $line = '[claude]'
}
Write-Output $line
exit 0
