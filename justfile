set windows-shell := ["powershell", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
_powershell_setup := if os() == "windows" { '& ./scripts/install_hooks.ps1' } else { 'pwsh -NoLogo -NoProfile -File scripts/install_hooks.ps1' }
_powershell_check := if os() == "windows" { '& ./scripts/check_powershell.ps1' } else { 'pwsh -NoLogo -NoProfile -File scripts/check_powershell.ps1' }

setup:
    {{_powershell_setup}}

pre-commit:
    bash -n video-maker/install.sh
    {{_powershell_check}}
