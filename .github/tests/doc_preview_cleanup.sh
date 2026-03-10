#!/usr/bin/env bash

set -euo pipefail

# This test covers the two cleanup cases the workflow itself cannot exercise on
# a normal PR run: preview exists and preview is already absent.
repo_root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
)"
cleanup_script="$repo_root/.github/scripts/doc_preview_cleanup.sh"
tmpdirs=()

cleanup() {
    if ((${#tmpdirs[@]} > 0)); then
        rm -rf "${tmpdirs[@]}"
    fi
}

make_repo() {
    local repo

    repo="$(mktemp -d)"
    tmpdirs+=("$repo")

    git -C "$repo" init -b gh-pages >/dev/null
    git -C "$repo" config user.name "Test User"
    git -C "$repo" config user.email "test@example.com"

    printf '%s\n' "$repo"
}

assert_file_contains() {
    local file="$1"
    local expected="$2"

    if ! grep -Fx "$expected" "$file" >/dev/null; then
        printf 'expected %s to contain %s\n' "$file" "$expected" >&2
        exit 1
    fi
}

assert_no_branch() {
    local repo="$1"
    local branch="$2"

    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
        printf 'did not expect branch %s in %s\n' "$branch" "$repo" >&2
        exit 1
    fi
}

trap cleanup EXIT

repo="$(make_repo)"
mkdir -p "$repo/previews/PR14"
touch "$repo/previews/PR14/index.html"
git -C "$repo" add .
git -C "$repo" commit -m "init" >/dev/null
output="$repo/output"
(
    cd "$repo"
    PRNUM=14 GITHUB_OUTPUT="$output" bash "$cleanup_script"
)

assert_file_contains "$output" "deleted=true"
git -C "$repo" rev-parse --verify gh-pages-new >/dev/null
if git -C "$repo" show HEAD:previews/PR14/index.html >/dev/null 2>&1; then
    printf 'expected previews/PR14/index.html to be deleted\n' >&2
    exit 1
fi

repo="$(make_repo)"
touch "$repo/keep.txt"
git -C "$repo" add keep.txt
git -C "$repo" commit -m "init" >/dev/null
head_before="$(git -C "$repo" rev-parse HEAD)"
output="$repo/output"
(
    cd "$repo"
    PRNUM=14 GITHUB_OUTPUT="$output" bash "$cleanup_script"
)
head_after="$(git -C "$repo" rev-parse HEAD)"

assert_file_contains "$output" "deleted=false"
assert_no_branch "$repo" "gh-pages-new"
if [[ "$head_before" != "$head_after" ]]; then
    printf 'expected HEAD to stay unchanged when no preview exists\n' >&2
    exit 1
fi

printf 'doc preview cleanup tests passed\n'
