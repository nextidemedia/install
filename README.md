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
