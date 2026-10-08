#!/usr/bin/env bash

set -euo pipefail

# Cleanup runs after PR close, so this logic lives in a versioned script that
# can be regression-tested on PRs before the close event ever happens.
: "${PRNUM:?PRNUM must be set}"

preview_path="${PREVIEW_PATH:-previews/PR${PRNUM}}"
commit_message="${COMMIT_MESSAGE:-delete preview}"
git_user_name="${GIT_USER_NAME:-Documenter.jl}"
git_user_email="${GIT_USER_EMAIL:-documenter@juliadocs.github.io}"

git config user.name "$git_user_name"
git config user.email "$git_user_email"

git rm -rf --ignore-unmatch -- "$preview_path"

if git diff --cached --quiet; then
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "deleted=false" >> "$GITHUB_OUTPUT"
    fi
    exit 0
fi

git commit -m "$commit_message"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "deleted=true" >> "$GITHUB_OUTPUT"
fi
