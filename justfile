set windows-shell := ["powershell", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
_hook_setup := if os() == "windows" { '& ./scripts/install_hooks.ps1' } else { 'sh scripts/install_hooks.sh' }
_platform_check := if os() == "windows" { '& ./scripts/check_powershell.ps1' } else { 'sh -n scripts/install_hooks.sh && sh -n .githooks/pre-commit' }

setup:
    {{_hook_setup}}

pre-commit:
    bash -n video-maker/install.sh
    {{_platform_check}}
