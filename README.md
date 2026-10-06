# video-maker installer

One-line setup for Nextide's video-maker (a private repository: you need an invite to the `nextidemedia` GitHub
organisation).

Windows (PowerShell):

    irm https://raw.githubusercontent.com/nextidemedia/video-maker-install/main/install.ps1 | iex

Mac with Apple silicon (Terminal):

    curl -fsSL https://raw.githubusercontent.com/nextidemedia/video-maker-install/main/install.sh | bash

The script installs Git and the GitHub CLI, signs you in to GitHub in your browser, clones video-maker to your home
folder, then runs the installer inside that clone, which sets up everything else.

These files are copies of `install.ps1` and `install.sh` from nextidemedia/video-maker. Change them there first.
