$input_json = [Console]::In.ReadToEnd() | ConvertFrom-Json
$model = $input_json.model.display_name
$dir = Split-Path -Leaf $input_json.workspace.current_dir
Write-Output "[$model] $dir"
