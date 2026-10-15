$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot
$shell = (Get-Process -Id $PID).Path
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('install-hooks-' + [guid]::NewGuid())
$originalLocation = Get-Location
$originalGlobal = $env:GIT_CONFIG_GLOBAL
$originalNoSystem = $env:GIT_CONFIG_NOSYSTEM

function Assert($condition, $message) {
    if (-not $condition) { throw $message }
}

function Git-Checked {
    $output = & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $args failed ($LASTEXITCODE)" }
    return $output
}

function New-Repository($name) {
    $path = Join-Path $sandbox $name
    New-Item -ItemType Directory $path | Out-Null
    foreach ($item in @('scripts', '.githooks', 'video-maker', 'justfile')) {
        Copy-Item -LiteralPath (Join-Path $project $item) -Destination $path -Recurse
    }
    Set-Location $path
    Git-Checked init -q | Out-Null
    return $path
}

function Setup($succeeds, $script = './scripts/install_hooks.ps1') {
    $log = Join-Path $sandbox 'setup.log'
    $ErrorActionPreference = 'Continue'
    & $shell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script *> $log
    $code = $LASTEXITCODE
    Assert (($code -eq 0) -eq $succeeds) ("Unexpected setup exit ${code}: " + (Get-Content $log -Raw))
}

try {
    New-Item -ItemType Directory $sandbox | Out-Null
    $env:GIT_CONFIG_GLOBAL = Join-Path $sandbox 'global-config'
    $env:GIT_CONFIG_NOSYSTEM = '1'

    $repo = New-Repository 'repo with spaces'
    # The public recipe must configure only the local clone and be repeatable.
    & just setup
    Assert ($LASTEXITCODE -eq 0) 'just setup failed'
    Assert ((Git-Checked config --local --get core.hooksPath) -eq '.githooks') 'Missing local hook path'
    $config = Get-Content .git/config -Raw
    $hook = Get-Content .githooks/pre-commit -Raw
    Setup $true
    Assert ((Get-Content .git/config -Raw) -ceq $config) 'Repeat setup changed config'
    Assert ((Get-Content .githooks/pre-commit -Raw) -ceq $hook) 'Setup changed tracked hook content'
    $alias = Join-Path $sandbox 'repo alias'
    $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path $alias -Target $repo | Out-Null
    Setup $true (Join-Path $alias 'scripts/install_hooks.ps1')
    Set-Location $alias
    Setup $true (Join-Path $repo 'scripts/install_hooks.ps1')
    Set-Location $repo
    [IO.Directory]::Delete($alias)

    & just pre-commit
    Assert ($LASTEXITCODE -eq 0) 'Clean syntax checks failed'
    foreach ($file in @('video-maker/install.sh', 'video-maker/install.ps1', 'scripts/install_hooks.ps1')) {
        $path = Join-Path $repo $file
        $bytes = [IO.File]::ReadAllBytes($path)
        try {
            Add-Content -LiteralPath $path "`nif ("
            $ErrorActionPreference = 'Continue'
            & just pre-commit *> (Join-Path $sandbox 'syntax.log')
            $code = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            Assert ($code -ne 0) "Syntax error in $file did not fail just pre-commit"
        }
        finally { [IO.File]::WriteAllBytes($path, $bytes) }
    }

    Git-Checked config --unset core.hooksPath | Out-Null
    Set-Content .git/hooks/pre-commit.sample 'sample'
    Setup $true
    Git-Checked config --unset core.hooksPath | Out-Null
    Set-Content .git/hooks/pre-commit 'existing hook'
    $config = Get-Content .git/config -Raw
    Setup $false
    Assert ((Get-Content .git/hooks/pre-commit -Raw).Trim() -eq 'existing hook') 'Default hook overwritten'
    Assert ((Get-Content .git/config -Raw) -ceq $config) 'Refusal changed config'
    Remove-Item .git/hooks/pre-commit

    foreach ($scope in @('--local', '--global')) {
        foreach ($value in @('custom hooks', '.GITHOOKS', '')) {
            # PowerShell 5.1 drops empty native arguments; write the empty value through Git's file format.
            $file = if ($scope -eq '--local') { '.git/config' } else { $env:GIT_CONFIG_GLOBAL }
            Add-Content $file "`n[core]`n    hooksPath = $value"
            $before = Get-Content $file -Raw
            Setup $false
            Assert ((Get-Content $file -Raw) -ceq $before) "$scope custom hook path changed"
            Git-Checked config $scope --unset core.hooksPath | Out-Null
        }
    }
    Git-Checked config --global core.hooksPath .githooks | Out-Null
    Setup $true
    & git config --local --get core.hooksPath | Out-Null
    Assert ($LASTEXITCODE -eq 1) 'Inherited path was changed locally'
    Git-Checked config --global --unset core.hooksPath | Out-Null

    Set-Location scripts
    Setup $false './install_hooks.ps1'
    Set-Location $repo
    New-Item -ItemType Directory nested | Out-Null
    Copy-Item scripts nested -Recurse
    Set-Location nested
    Setup $false
    $other = New-Repository 'other'
    Setup $false (Join-Path $repo 'scripts/install_hooks.ps1')
    if ($env:OS -ne 'Windows_NT') {
        $linkedScript = Join-Path $other 'scripts/install_hooks.ps1'
        Remove-Item -LiteralPath $linkedScript
        New-Item -ItemType SymbolicLink -Path $linkedScript -Target (Join-Path $repo 'scripts/install_hooks.ps1') | Out-Null
        Setup $false
        Set-Location $repo
        Setup $true $linkedScript
        Git-Checked config --local --unset core.hooksPath | Out-Null
    }
    Set-Location $sandbox
    Setup $false (Join-Path $repo 'scripts/install_hooks.ps1')

    Set-Location $repo
    Rename-Item .githooks/pre-commit missing
    Setup $false
    Rename-Item .githooks/missing pre-commit
    New-Item -ItemType File .git/config.lock | Out-Null
    Setup $false
    Remove-Item .git/config.lock
    & git config --local --get core.hooksPath | Out-Null
    Assert ($LASTEXITCODE -eq 1) 'Failed config write activated hooks'

    Git-Checked -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m fixture
    $linked = Join-Path $sandbox 'linked worktree'
    Git-Checked worktree add -q -b linked $linked | Out-Null
    foreach ($item in @('scripts', '.githooks', 'justfile')) {
        Copy-Item -LiteralPath (Join-Path $project $item) -Destination $linked -Recurse
    }
    Set-Location $linked
    Setup $true
    Git-Checked config --local --unset core.hooksPath | Out-Null
    Set-Content (Join-Path $repo '.git/hooks/pre-commit') 'shared hook'
    Setup $false
    Assert ((Get-Content (Join-Path $repo '.git/hooks/pre-commit') -Raw).Trim() -eq 'shared hook') 'Shared hook changed'

    Write-Host 'Hook setup process checks passed.'
}
finally {
    Set-Location $originalLocation
    $env:GIT_CONFIG_GLOBAL = $originalGlobal
    $env:GIT_CONFIG_NOSYSTEM = $originalNoSystem
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
