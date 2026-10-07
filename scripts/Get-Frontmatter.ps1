function Get-Frontmatter {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) { $raw = '' }
    $lines = $raw -split '\r?\n'
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') {
        throw "Frontmatter ausente: $Path"
    }
    $close = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $close = $i; break }
    }
    if ($close -lt 0) {
        throw "Frontmatter ausente: $Path"
    }
    $result = [ordered]@{}
    for ($i = 1; $i -lt $close; $i++) {
        $idx = $lines[$i].IndexOf(':')
        if ($idx -lt 1) { continue }
        $key = $lines[$i].Substring(0, $idx).Trim()
        $result[$key] = $lines[$i].Substring($idx + 1).Trim()
    }
    return $result
}
