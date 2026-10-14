$ErrorActionPreference = 'Stop'
$failed = $false
foreach ($file in @('video-maker/install.ps1', 'scripts/check_powershell.ps1')) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path (Split-Path $PSScriptRoot) $file), [ref]$tokens, [ref]$errors
    ) | Out-Null
    foreach ($parseError in $errors) {
        Write-Host ($file + ': ' + $parseError.Message)
        $failed = $true
    }
}
if ($failed) { exit 1 }
