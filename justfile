set windows-shell := ["powershell", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
_python := if os() == "windows" { "python" } else { "python3" }
_powershell_check := if os() == "windows" { '& ./scripts/check_powershell.ps1' } else { 'pwsh -NoLogo -NoProfile -File scripts/check_powershell.ps1' }

setup:
    {{_python}} scripts/install_hooks.py

pre-commit:
    bash -n video-maker/install.sh
    {{_powershell_check}}
    {{_python}} -c "from pathlib import Path; compile(Path('scripts/install_hooks.py').read_text(), 'scripts/install_hooks.py', 'exec')"
