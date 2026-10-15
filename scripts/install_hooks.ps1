$ErrorActionPreference = 'Stop'

$root = & git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$prefix = & git rev-parse --show-prefix
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$project = Join-Path $PSScriptRoot '..'
$projectRoot = & git -C $project rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$projectPrefix = & git -C $project rev-parse --show-prefix
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Let Git resolve linked paths; PowerShell's Resolve-Path retains symlink spellings.
$comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if ($prefix -or $projectPrefix -or -not [string]::Equals($root, $projectRoot, $comparison)) {
    throw 'Run git init in this project, then run hook setup from its root.'
}

$configured = & git config --get core.hooksPath
if ($LASTEXITCODE -eq 0) {
    if ($configured -ceq '.githooks') { exit 0 }
    throw 'Existing core.hooksPath preserved; integrate just pre-commit there explicitly.'
}
if ($LASTEXITCODE -ne 1) { exit $LASTEXITCODE }

$defaultHooks = & git rev-parse --git-path hooks
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$hookNames = @(
    'applypatch-msg', 'pre-applypatch', 'post-applypatch', 'pre-commit',
    'pre-merge-commit', 'prepare-commit-msg', 'commit-msg', 'post-commit',
    'pre-rebase', 'post-checkout', 'post-merge', 'pre-push', 'pre-receive',
    'update', 'proc-receive', 'post-receive', 'post-update', 'reference-transaction',
    'push-to-checkout', 'pre-auto-gc', 'post-rewrite', 'sendemail-validate',
    'fsmonitor-watchman', 'p4-changelist', 'p4-prepare-changelist',
    'p4-post-changelist', 'p4-pre-submit', 'post-index-change'
)
if ((Test-Path -LiteralPath $defaultHooks) -and
    (Get-ChildItem -LiteralPath $defaultHooks -Force | Where-Object { $_.Name -cin $hookNames })) {
    throw 'Existing Git hooks preserved; integrate just pre-commit there explicitly.'
}
$hook = Join-Path $projectRoot '.githooks/pre-commit'
if (-not (Test-Path -LiteralPath $hook -PathType Leaf)) {
    throw 'Missing tracked .githooks/pre-commit.'
}
if ($env:OS -ne 'Windows_NT') {
    & chmod a+x $hook
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& git config --local core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
