#!/bin/sh
set -eu

root=$(git rev-parse --show-toplevel)
prefix=$(git rev-parse --show-prefix)
# Resolve directory aliases and script symlinks before comparing repositories.
script=$0
while :; do
    directory=$(CDPATH= cd -P -- "$(dirname -- "$script")" && pwd)
    script=$directory/$(basename -- "$script")
    [ -L "$script" ] || break
    target=$(readlink "$script")
    case $target in
        /*) script=$target ;;
        *) script=$directory/$target ;;
    esac
done
project=$(dirname -- "$directory")
project_root=$(git -C "$project" rev-parse --show-toplevel)
project_prefix=$(git -C "$project" rev-parse --show-prefix)
if [ -n "$prefix" ] || [ -n "$project_prefix" ] || [ "$root" != "$project_root" ]; then
    echo 'Run git init in this project, then run hook setup from its root.' >&2
    exit 1
fi

if configured=$(git config --get core.hooksPath); then
    [ "$configured" != '.githooks' ] || exit 0
    echo 'Existing core.hooksPath preserved; integrate just pre-commit there explicitly.' >&2
    exit 1
else
    code=$?
    [ "$code" -eq 1 ] || exit "$code"
fi

hooks=$(git rev-parse --git-path hooks)
for hook in "$hooks"/* "$hooks"/.[!.]* "$hooks"/..?*; do
    case ${hook##*/} in
        applypatch-msg|pre-applypatch|post-applypatch|pre-commit|pre-merge-commit|prepare-commit-msg|commit-msg|post-commit|pre-rebase|post-checkout|post-merge|pre-push|pre-receive|update|proc-receive|post-receive|post-update|reference-transaction|push-to-checkout|pre-auto-gc|post-rewrite|sendemail-validate|fsmonitor-watchman|p4-changelist|p4-prepare-changelist|p4-post-changelist|p4-pre-submit|post-index-change)
            if [ -e "$hook" ] || [ -L "$hook" ]; then
                echo 'Existing Git hooks preserved; integrate just pre-commit there explicitly.' >&2
                exit 1
            fi ;;
    esac
done
hook=$project_root/.githooks/pre-commit
if [ ! -f "$hook" ]; then
    echo 'Missing tracked .githooks/pre-commit.' >&2
    exit 1
fi
chmod a+x "$hook"
git config --local core.hooksPath .githooks
