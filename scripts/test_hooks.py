"""Unix process checks in disposable standalone repositories; no dependencies."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parent.parent


def run(*args, cwd, ok=True):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    assert (result.returncode == 0) == ok, (
        f"{args}: exit {result.returncode}\n{result.stdout}{result.stderr}"
    )
    return result.stdout.strip()


def repository(sandbox, name):
    repo = sandbox / name
    repo.mkdir()
    for name in ("scripts", ".githooks", "video-maker"):
        shutil.copytree(PROJECT / name, repo / name)
    shutil.copy2(PROJECT / "justfile", repo / "justfile")
    run("git", "init", "-q", cwd=repo)
    return repo


def setup(repo, ok=True, script="scripts/install_hooks.sh"):
    run("sh", str(script), cwd=repo, ok=ok)


def check(sandbox):
    repo = repository(sandbox, "repo with spaces")
    hook = repo / ".githooks/pre-commit"
    hook.chmod(0o644)
    run("just", "setup", cwd=repo)
    assert os.access(hook, os.X_OK), "Hook not executable"
    config = repo / ".git/config"
    before = config.read_bytes()
    setup(repo)
    assert config.read_bytes() == before, "Repeat setup changed config"
    alias = sandbox / "repo alias"
    alias.symlink_to(repo, target_is_directory=True)
    setup(repo, script=alias / "scripts/install_hooks.sh")
    setup(alias, script=repo / "scripts/install_hooks.sh")
    run("just", "pre-commit", cwd=repo)

    # Exercise Git's real hook invocation and prove syntax failures stop a commit.
    commit = ("git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
              "commit", "-q", "--allow-empty", "-m", "fixture")
    run(*commit, cwd=repo)
    for name in ("video-maker/install.sh", "scripts/install_hooks.sh", ".githooks/pre-commit"):
        file = repo / name
        original = file.read_bytes()
        head = run("git", "rev-parse", "HEAD", cwd=repo)
        try:
            file.write_bytes(original + b"\nif (\n")
            run("just", "pre-commit", cwd=repo, ok=False)
            run(*commit, cwd=repo, ok=False)
            assert run("git", "rev-parse", "HEAD", cwd=repo) == head
            assert file.read_bytes() == original + b"\nif (\n", "Check changed input"
        finally:
            file.write_bytes(original)

    run("git", "config", "--unset", "core.hooksPath", cwd=repo)
    (repo / ".git/hooks/pre-commit.sample").write_text("sample")
    setup(repo)
    run("git", "config", "--unset", "core.hooksPath", cwd=repo)
    default = repo / ".git/hooks/pre-commit"
    default.write_text("existing hook")
    before = config.read_bytes()
    setup(repo, ok=False)
    assert default.read_text() == "existing hook"
    assert config.read_bytes() == before
    default.unlink()

    for scope, file in (("--local", config), ("--global", Path(os.environ["GIT_CONFIG_GLOBAL"]))):
        for value in ("custom hooks", ".GITHOOKS", ""):
            run("git", "config", scope, "core.hooksPath", value, cwd=repo)
            before = file.read_bytes()
            setup(repo, ok=False)
            assert file.read_bytes() == before, "Custom configuration changed"
            run("git", "config", scope, "--unset", "core.hooksPath", cwd=repo)
    run("git", "config", "--global", "core.hooksPath", ".githooks", cwd=repo)
    setup(repo)
    run("git", "config", "--local", "--get", "core.hooksPath", cwd=repo, ok=False)
    run("git", "config", "--global", "--unset", "core.hooksPath", cwd=repo)

    setup(repo / "scripts", ok=False, script="install_hooks.sh")
    nested = repo / "nested"
    shutil.copytree(repo / "scripts", nested / "scripts")
    setup(nested, ok=False)
    other = repository(sandbox, "other")
    setup(other, ok=False, script=repo / "scripts/install_hooks.sh")
    link = other / "scripts/install_hooks.sh"
    link.unlink()
    link.symlink_to(os.path.relpath(repo / "scripts/install_hooks.sh", link.parent))
    setup(other, ok=False)
    setup(repo, script=link)
    run("git", "config", "--unset", "core.hooksPath", cwd=repo)
    setup(sandbox, ok=False, script=repo / "scripts/install_hooks.sh")

    hook.rename(hook.with_name("missing"))
    setup(repo, ok=False)
    hook.with_name("missing").rename(hook)
    lock = repo / ".git/config.lock"
    lock.touch()
    setup(repo, ok=False)
    lock.unlink()
    run("git", "config", "--local", "--get", "core.hooksPath", cwd=repo, ok=False)

    # This linked worktree belongs only to the disposable fixture repository.
    linked = sandbox / "linked worktree"
    run("git", "worktree", "add", "-q", "-b", "linked", str(linked), cwd=repo)
    for name in ("scripts", ".githooks"):
        shutil.copytree(PROJECT / name, linked / name)
    setup(linked)
    run("git", "config", "--unset", "core.hooksPath", cwd=repo)
    default.write_text("shared hook")
    setup(linked, ok=False)
    assert default.read_text() == "shared hook"


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="install-hooks-") as temporary:
        sandbox = Path(temporary)
        # Isolate inherited hook configuration and commit signing from the host.
        os.environ["GIT_CONFIG_GLOBAL"] = str(sandbox / "global-config")
        os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
        check(sandbox)
    print("Hook setup and real commit checks passed.")
