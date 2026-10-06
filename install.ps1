# Windows 10/11 x64; paste the public copy into PowerShell, or run this copy in the repo.
[CmdletBinding()]
param(
    [string]$Dir = $env:VIDEO_MAKER_DIR,
    [string]$Ref = 'main',
    [ValidateSet('', 'claude', 'codex', 'skip')][string]$Agent = '',
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

function Find-Tool([string]$Name) {
    $tool = Get-Command "$Name.cmd", "$Name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tool) { return $tool.Source }
}

function Test-Command([string]$Command, [string[]]$CommandArgs) {
    if (-not $Command) { return $false }
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue' # Native stderr is not a failure in Windows PowerShell 5.1.
    try { & $Command @CommandArgs > $null 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $saved }
    return $code -eq 0
}

function Run-Step([string]$Label, [string]$Command, [string[]]$CommandArgs) {
    if (-not (Test-Command $Command $CommandArgs)) { throw "$Label failed. See the manual setup in START_HERE.md, then rerun." }
    Write-Host "ok    $Label"
}

function Refresh-Path {
    $env:Path = @(
        $env:Path
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
        "$env:APPDATA\npm"
    ) -join ';'
}

function Require-Tool([string]$Name, [string]$Package) {
    if (Find-Tool $Name) { Write-Host "skip  $Name already installed"; return }
    if (-not (Find-Tool 'winget')) { throw 'Install App Installer from the Microsoft Store, then rerun.' }
    Run-Step "Install $Name (allow changes if asked)" (Find-Tool 'winget') @(
        'install', '--id', $Package, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    Refresh-Path
    if (-not (Find-Tool $Name)) { throw "$Name is not available yet. Open a new PowerShell window and rerun." }
}

function Check-Folder([string]$Path) {
    if ($Path -match '(?i)(^|[\\/])(OneDrive[^\\/]*|iCloud(?:Drive| Drive)?)([\\/]|$)') {
        throw 'Choose a folder outside OneDrive or iCloud Drive with VIDEO_MAKER_DIR or -Dir.'
    }
    foreach ($cloud in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) {
        if ($cloud -and ($Path.TrimEnd('\') -eq $cloud.TrimEnd('\') -or
            $Path.StartsWith($cloud.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))) {
            throw 'Choose a folder outside OneDrive with VIDEO_MAKER_DIR or -Dir.'
        }
    }
}

if ($env:OS -ne 'Windows_NT' -or [Environment]::OSVersion.Version.Major -lt 10 -or
    (Get-CimInstance Win32_Processor | Select-Object -First 1).Architecture -ne 9) {
    throw 'This installer needs Windows 10/11 on an x64 PC. Windows ARM is not supported.'
}
if (-not [Environment]::Is64BitProcess) { throw 'Open the 64-bit version of PowerShell and rerun.' }
Write-Host 'ok    Supported Windows PC'
Refresh-Path

$repo = ''
foreach ($candidate in @($PSScriptRoot, (Get-Location).Path)) {
    if ($candidate -and (Test-Path -LiteralPath "$candidate/tools/doctor.py") -and
        (Test-Path -LiteralPath "$candidate/.git")) { $repo = $candidate; break }
}
if (-not $repo) {
    if (-not $Dir) { $Dir = Join-Path $env:USERPROFILE 'video-maker' }
    $Dir = [IO.Path]::GetFullPath($Dir)
    Check-Folder $Dir
    Require-Tool 'git' 'Git.Git'
    Require-Tool 'gh' 'GitHub.cli'
    if (-not (Test-Path -LiteralPath $Dir)) {
        if (-not (Test-Command (Find-Tool 'gh') @('auth', 'status', '--hostname', 'github.com'))) {
            if ($NonInteractive) { throw 'Sign in with gh auth login, then rerun.' }
            Write-Host 'fix   Sign in to GitHub in your browser'
            & (Find-Tool 'gh') auth login --hostname github.com --git-protocol https --web
            if ($LASTEXITCODE -ne 0) { throw 'GitHub sign-in failed. Accept your organisation invite, then rerun.' }
        }
        Run-Step 'Download video-maker' (Find-Tool 'gh') @(
            'repo', 'clone', 'nextidemedia/video-maker', $Dir, '--', '--branch', $Ref
        )
    } else { Write-Host 'skip  Existing folder (no update)' }
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $origin = & (Find-Tool 'git') -C $Dir remote get-url origin 2>$null; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $saved }
    if ($code -ne 0 -or $origin -notmatch 'github\.com[:/]nextidemedia/video-maker(?:\.git)?$' -or
        -not (Test-Path -LiteralPath "$Dir/install.ps1")) {
        throw 'The chosen folder is not a video-maker clone with the installer. Choose another -Dir.'
    }
    Push-Location $Dir
    try {
        # Scriptblock also works when local PowerShell script execution is restricted.
        & ([scriptblock]::Create([IO.File]::ReadAllText("$Dir/install.ps1"))) -Agent $Agent -NonInteractive:$NonInteractive
    } finally { Pop-Location }
    return
}

Check-Folder $repo
Push-Location $repo
try {
    foreach ($tool in @(
        @('git', 'Git.Git'), @('gh', 'GitHub.cli'), @('uv', 'astral-sh.uv'),
        @('node', 'OpenJS.NodeJS.LTS'), @('ffmpeg', 'Gyan.FFmpeg')
    )) { Require-Tool $tool[0] $tool[1] }
    $chrome = @($env:CHROME, "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    if ($chrome) { Write-Host 'skip  Google Chrome already installed' }
    else { Run-Step 'Install Google Chrome (allow changes if asked)' (Find-Tool 'winget') @(
        'install', '--id', 'Google.Chrome', '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements'
    ) }
    if ([Environment]::GetEnvironmentVariable('PYTHONUTF8', 'User') -ne '1') {
        Run-Step 'Enable international text' 'setx.exe' @('PYTHONUTF8', '1')
    } else { Write-Host 'skip  International text already enabled' }
    $env:PYTHONUTF8 = '1'
    Run-Step 'Enable long file names' (Find-Tool 'git') @('config', '--global', 'core.longpaths', 'true')
    foreach ($key in @('user.name', 'user.email')) {
        $value = & (Find-Tool 'git') config $key 2>$null
        if (-not $value) {
            if ($NonInteractive) { throw "Set git config --global $key before running without prompts." }
            $label = if ($key -eq 'user.name') { 'Your name for Git' } else { 'Your email for Git (saved locally)' }
            $value = Read-Host $label
            if (-not $value.Trim()) { throw 'A name and email are needed for Git. Rerun when ready.' }
            Run-Step 'Save Git identity locally' (Find-Tool 'git') @('config', '--global', $key, $value)
        }
    }
    Run-Step 'Install the video toolkit' (Find-Tool 'uv') @('sync', '--locked')

    # Let the existing doctor decide which installed tools need repair.
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $check = (& (Find-Tool 'uv') run python tools/doctor.py 2>&1) -join "`n" }
    finally { $ErrorActionPreference = $saved }
    foreach ($repair in @(@('Node', 'OpenJS.NodeJS.LTS'), @('ffmpeg', 'Gyan.FFmpeg'))) {
        if ($check -match "FIX\s+$($repair[0]):.*(?:older than|need 7 or newer)") {
            Run-Step "Update $($repair[0]) (doctor requires it)" (Find-Tool 'winget') @(
                'upgrade', '--id', $repair[1], '--exact', '--source', 'winget',
                '--accept-source-agreements', '--accept-package-agreements'
            )
            Refresh-Path
        }
    }
    $projects = & (Find-Tool 'git') ls-files -- 'projects/*/package.json'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot find the sample projects. Check this clone and rerun.' }
    foreach ($file in $projects) {
        Push-Location (Split-Path $file)
        try { Run-Step "Prepare $(Split-Path (Split-Path $file) -Leaf)" (Find-Tool 'npm') @('ci', '--no-audit', '--no-fund') }
        finally { Pop-Location }
    }
    if (-not $Agent) {
        if ($NonInteractive) { $Agent = 'skip' }
        elseif (Find-Tool 'claude') { $Agent = 'claude' }
        elseif (Find-Tool 'codex') { $Agent = 'codex' }
        else {
            $Agent = (Read-Host 'Claude Code, Codex, or skip? [claude]').Trim().ToLowerInvariant()
            if (-not $Agent -or $Agent -eq 'claude code') { $Agent = 'claude' }
        }
    }
    if ($Agent -notin @('claude', 'codex', 'skip')) { throw 'Choose claude, codex, or skip, then rerun.' }
    if ($Agent -ne 'skip') {
        if (-not (Find-Tool $Agent)) {
            $package = if ($Agent -eq 'claude') { '@anthropic-ai/claude-code' } else { '@openai/codex' }
            $before = (Get-Date).ToUniversalTime().AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ')
            Run-Step "Install $Agent" (Find-Tool 'npm') @('install', '-g', "$package@*", "--before=$before", '--no-audit', '--no-fund')
            Refresh-Path
        } else { Write-Host "skip  $Agent already installed" }
        if (-not (Test-Command (Find-Tool $Agent) @('mcp', 'get', 'nextide'))) {
            $add = if ($Agent -eq 'claude') { @('mcp', 'add', '--transport', 'http', '--scope', 'user', 'nextide', 'https://mcp.nextide.io/mcp') }
                   else { @('mcp', 'add', 'nextide', '--url', 'https://mcp.nextide.io/mcp') }
            Run-Step 'Connect Nextide data' (Find-Tool $Agent) $add
        } else { Write-Host 'skip  Nextide already configured' }
        if ($Agent -eq 'claude') { Write-Host 'next  In Claude Code, use /mcp to sign in with your Nextide Google account.' }
        else { Write-Host 'next  Run codex mcp login nextide to sign in with your Nextide Google account.' }
    } else { Write-Host 'skip  Agent setup; connect Nextide later using START_HERE.md.' }

    & (Find-Tool 'uv') run python tools/doctor.py
    if ($LASTEXITCODE -ne 0) { throw 'Fix the items above, then rerun the installer.' }
    Write-Host "next  Open your agent in $repo and say what you want."
} finally { Pop-Location }
