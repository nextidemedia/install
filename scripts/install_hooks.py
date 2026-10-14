"""Activate the tracked hooks without replacing existing local hooks."""

import subprocess
from pathlib import Path


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


def main() -> None:
    root = Path(git("rev-parse", "--show-toplevel"))
    project = Path(__file__).resolve().parents[1]
    if project != root.resolve() or Path.cwd().resolve() != project:
        raise SystemExit(
            "Run git init in this project, then run hook setup from its root."
        )
    configured = subprocess.run(
        ["git", "config", "--get", "core.hooksPath"],
        capture_output=True,
        text=True,
        check=False,
    )
    if configured.returncode not in (0, 1):
        raise SystemExit(configured.stderr)
    if configured.returncode == 0:
        if configured.stdout.strip() == ".githooks":
            return
        raise SystemExit(
            "Existing core.hooksPath preserved; integrate just pre-commit there explicitly."
        )
    default_hooks = Path(git("rev-parse", "--git-path", "hooks"))
    hook_names = {
        "applypatch-msg",
        "pre-applypatch",
        "post-applypatch",
        "pre-commit",
        "pre-merge-commit",
        "prepare-commit-msg",
        "commit-msg",
        "post-commit",
        "pre-rebase",
        "post-checkout",
        "post-merge",
        "pre-push",
        "pre-receive",
        "update",
        "proc-receive",
        "post-receive",
        "post-update",
        "reference-transaction",
        "push-to-checkout",
        "pre-auto-gc",
        "post-rewrite",
        "sendemail-validate",
        "fsmonitor-watchman",
        "p4-changelist",
        "p4-prepare-changelist",
        "p4-post-changelist",
        "p4-pre-submit",
        "post-index-change",
    }
    if default_hooks.exists() and any(
        hook.name in hook_names for hook in default_hooks.iterdir()
    ):
        raise SystemExit(
            "Existing Git hooks preserved; integrate just pre-commit there explicitly."
        )
    hook = root / ".githooks" / "pre-commit"
    if not hook.is_file():
        raise SystemExit("Missing tracked .githooks/pre-commit.")
    hook.chmod(hook.stat().st_mode | 0o111)
    subprocess.run(
        ["git", "config", "--local", "core.hooksPath", ".githooks"], check=True
    )


if __name__ == "__main__":
    main()
