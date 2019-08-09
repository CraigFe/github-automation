#!/bin/bash
set -euo pipefail

# This script:
#  - clones an OCaml repository on GitHub
#  - upgrades the OCamlformat version to match the currently-installed version
#  - on confirmation, forks the repository and submits a PR requesting the upgrade

usage () {
    cat >&2 <<EOF
$0 [ORG] [REPO]
EOF
    exit 1
}

[ $# -eq 2 ] || usage

command -v hub >/dev/null 2>&1 || { echo >&2 "Missing dependency 'hub'"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "Missing dependency 'jq'"; exit 1; }

ORG="$1"
REPO="$2"
VERSION="$(ocamlformat --version)"
USER=$(hub api user | jq --raw-output ".login")
BRANCH="ocamlformat.$VERSION"
GIT_DIR="/tmp/autoformatted"
MESSAGE_FILE="/tmp/autoformat_message.md"

cat <<EOF > $MESSAGE_FILE
Upgrade to OCamlformat v$VERSION

- reformats the code to be compliant with OCamlformat v$VERSION
- updates the \`.ocamlformat\` file accordingly
EOF

COLOR_RESET="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_GREENB="\033[1;32m"
COLOR_PURPLEB="\033[1;35m"
COLOR_CYAN="\033[0;36m"

function action {
    echo -e "$COLOR_CYAN<><><><> $COLOR_GREENB${1}$COLOR_CYAN <><><><>$COLOR_RESET\n"
}

function prompt {
    read -p "$(echo -e "${COLOR_PURPLEB}Issue a PR?${COLOR_RESET} [${COLOR_GREEN}y${COLOR_RESET}/${COLOR_RED}N${COLOR_RESET}]" )" -n 1 -r
}

# ------------------------------------------------------------------------------
action "Cloning $ORG/$REPO"
# ------------------------------------------------------------------------------

[[ ! -d "/tmp/autoformatted" ]] || {
    echo "Removing existing tmp directory at $GIT_DIR..."
    rm -rf "$GIT_DIR"
}

hub clone --origin upstream "$ORG/$REPO" "$GIT_DIR"
echo
cd "$GIT_DIR" || exit 2

# Update the OCamlformat version
VERSION_OLD="$(grep version .ocamlformat | cut -d= -f2 | awk '{$1=$1};1')"

sed -i "/^version.*/c\version = ${VERSION}" .ocamlformat
[[ -n "$(git ls-files --modified .ocamlformat)" ]] || {
    echo "Already using OCamlformat v${VERSION}"
    exit 3
}

# ------------------------------------------------------------------------------
action "Upgrading ocamlformat.$VERSION_OLD to ocamlformat.$VERSION"
# ------------------------------------------------------------------------------

dune build @fmt --auto-promote --diff-command=- 2>/dev/null || true

git add -u
git diff --stat --cached HEAD
echo

echo "Active PRs on $ORG/$REPO:"
hub pr list
echo

prompt
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 4
echo

# ------------------------------------------------------------------------------
action "Forking $ORG/$REPO"
# ------------------------------------------------------------------------------

hub fork
git remote rename "$USER" origin
echo

# If the branch already exists at the origin, delete it first
git fetch --quiet --prune origin
if git show-ref --quiet --verify "refs/remotes/origin/$BRANCH"; then
    echo "Deleting existing branch $USER/$BRANCH"
    git push --quiet origin --delete "$BRANCH"
fi

git checkout --quiet -B "$BRANCH"
git commit --quiet -m "Use ocamlformat.${VERSION}"
git push --quiet -u origin "$BRANCH" >/dev/null 2>&1
echo

# ------------------------------------------------------------------------------
action "Issuing PR to $ORG/$REPO"
# ------------------------------------------------------------------------------

hub pull-request --file /tmp/message
