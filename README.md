# Nextide installers

One-line setup scripts for Nextide's internal tools. Each tool's repository is private; you need an invite to the
`nextidemedia` GitHub organisation. The scripts here hold no secrets or data: they install the basics, sign you in to
GitHub in your browser, clone the private repository and run the full installer inside it.

## video-maker

Code-rendered campaign videos and client proof packages.

Windows 10/11 (PowerShell):

    irm https://raw.githubusercontent.com/nextidemedia/install/main/video-maker/install.ps1 | iex

Mac with Apple silicon (Terminal):

    curl -fsSL https://raw.githubusercontent.com/nextidemedia/install/main/video-maker/install.sh | bash

The files in `video-maker/` are copies of `install.ps1` and `install.sh` from nextidemedia/video-maker. Change them
there first, then copy them here.

## Adding an installer

Put it in a folder named after the tool (`<tool>/install.ps1`, `<tool>/install.sh`), keep the public copy limited to
bootstrapping (install Git and the GitHub CLI, sign in, clone, hand over to the repository's own installer), and add a
section above.

## Developer checks

With Git, just and Bash already installed, run `just setup` from this
clone to activate the tracked Git hook. Windows uses Windows PowerShell 5.1;
macOS/Linux use `sh` and do not need PowerShell. Setup writes the local Git
hook configuration. Run it in a standalone clone: linked worktrees share that
configuration with their main checkout.
Existing custom hook paths/default hooks are preserved; integrate
`just pre-commit` there explicitly if setup reports a conflict.

`just pre-commit` parses the Bash installer and native developer shell scripts
on Unix. On Windows it parses the Bash installer and uses the PowerShell parser
for the PowerShell installer and developer scripts. It checks the working tree without running installers, downloading
tools, or changing source/staged files. These syntax checks do not prove installer
behavior or macOS Bash 3.2 compatibility; product installer copies stay owned by
`video-maker` as described above. There is no CI workflow in this repository.

PowerShell source qualification remains a Windows check; Unix shell checks do
not validate PowerShell syntax.

On Unix, run `python3 scripts/test_hooks.py`. On Windows, run
`scripts/test_hooks.ps1` with the same PowerShell to check hook setup against
temporary Git repositories, including existing hook and linked-worktree cases.
