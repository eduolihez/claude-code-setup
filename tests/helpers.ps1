function Test-GitIgnored {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Path
    )
    & git -C $RepoRoot check-ignore -q -- $Path 2>$null
    return ($LASTEXITCODE -eq 0)
}
