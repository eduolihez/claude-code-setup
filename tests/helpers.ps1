function Test-GitIgnored {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Path
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $RepoRoot check-ignore -q --no-index -- $Path 2>$null
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
    return ($code -eq 0)
}

function Invoke-Script {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$StdinText = '',
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 60
    )
    # Quote an argument for a Windows command line (handles spaces and quotes).
    $quote = { param($a) '"' + ($a -replace '(\*)"', '$1$1\"' -replace '(\+)$', '$1$1') + '"' }
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $quote $Path))
    foreach ($a in $Arguments) { $parts += (& $quote $a) }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($parts -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    try {
        # Read both streams asynchronously to avoid pipe deadlocks.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        # Write stdin as UTF-8 bytes without BOM, then close it.
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($StdinText)
        try {
            if ($bytes.Length -gt 0) { $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length) }
            $proc.StandardInput.Close()
        }
        catch [System.IO.IOException] { }
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch { }
            throw "Invoke-Script: timeout de $TimeoutSeconds s ejecutando $Path"
        }
        $proc.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Stdout   = $outTask.Result
            Stderr   = $errTask.Result
        }
    }
    finally {
        $proc.Dispose()
    }
}
