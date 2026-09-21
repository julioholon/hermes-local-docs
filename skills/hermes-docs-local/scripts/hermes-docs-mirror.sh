#!/usr/bin/env bash
# hermes-docs-mirror.sh — make the Hermes docs available offline on a locked-down network.
#
# WHY: the bundled `hermes-agent` skill links to https://hermes-agent.nousresearch.com/docs/*.
# Networks that classify by DOMAIN CATEGORY block that host as "AI-related", so it 403s and the
# agent fails whenever it tries to consult the docs.
#
# What this gives you: (A) a markdown mirror the AGENT reads with read_file / search_files — no
# HTML, no server, fastest path. Nothing else. It does NOT build or serve the website.
#
# Browsing the docs as a website needs no script at all — do it in a checkout:
#
#   cd <clone>/website && npm install && npm run start     # http://localhost:3000/docs/
#
# `docusaurus start` is a dev server: no build step, and it honours the upstream baseUrl, so
# /docs/ links and assets all resolve. For a static copy to host on nginx/caddy instead use
# `npm run build && npm run serve` in that same directory (the build output is served under
# /docs/; mount it there, e.g. `location /docs/ { alias <website>/build/; }`).
#
# Usage:
#   ./hermes-docs-mirror.sh                            # markdown mirror (fresh /tmp clone)
#   ./hermes-docs-mirror.sh --src ~/src/hermes-agent    # from an EXISTING clone (no download)
#   ./hermes-docs-mirror.sh --src ~/src/hermes-agent --pull   # update that clone first, then copy
#   DEST=/some/path ./hermes-docs-mirror.sh
#   HERMES_SRC=~/src/hermes-agent ./hermes-docs-mirror.sh      # env equivalent of --src
#
# Options:
#   --src PATH    Use an existing hermes-agent checkout instead of cloning one into /tmp.
#                 Skips the sparse clone entirely (the repo is large and you may already have it,
#                 e.g. ~/src/hermes-agent). Validated to look like a Hermes tree (must contain
#                 website/docs). No network access at all in this mode.
#   --pull        With --src: `git pull --ff-only` that checkout first so the mirror is fresh.
#                 A failure (diverged/dirty/offline) only warns — the tree is used as-is.
#   -h, --help    Show this help.
#
# Env: DEST (default /opt/data/docs/hermes), HERMES_SRC (default of --src).

set -euo pipefail

DEST="${DEST:-/opt/data/docs/hermes}"
SRC="${HERMES_SRC:-}"

usage() { sed -n '/^# Usage:/,/^# Env:/p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)     [[ $# -ge 2 ]] || { echo "ERROR: --src needs a path" >&2; exit 2; }
                   SRC="$2"; shift 2 ;;
        --src=*)   SRC="${1#*=}"; shift ;;
        --pull)    PULL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "ERROR: unknown argument: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    esac
done
PULL="${PULL:-0}"

TMP=""
trap '[[ -n "$TMP" ]] && rm -rf "$TMP"' EXIT

if [[ -n "$SRC" ]]; then
    # Expanding a leading ~ ourselves: it is not expanded inside quoted strings.
    SRC="${SRC/#\~/$HOME}"
    if [[ ! -d "$SRC" ]]; then
        echo "ERROR: --src is not a directory: $SRC" >&2
        exit 1
    fi
    SRC="$(cd "$SRC" && pwd)"
    if [[ ! -d "$SRC/website/docs" ]]; then
        echo "ERROR: $SRC does not look like a hermes-agent checkout (no website/docs/)." >&2
        echo "       Pass the repo ROOT (e.g. ~/src/hermes-agent), not a subdirectory." >&2
        exit 1
    fi
    echo "==> using existing checkout: $SRC (no clone, no download)"
    if [[ "$PULL" == "1" ]]; then
        echo "==> refreshing that checkout (git pull --ff-only)"
        git -C "$SRC" pull --ff-only \
            || echo "    WARN: pull failed (diverged/dirty/offline) — using the tree as-is"
    fi
else
    TMP="$(mktemp -d)"
    echo "==> fetching docs source (sparse, depth=1) -> $TMP/src"
    git clone --depth 1 --filter=blob:none --sparse \
        https://github.com/NousResearch/hermes-agent "$TMP/src"
    git -C "$TMP/src" sparse-checkout set website/docs scripts/build_skills_index.py
    SRC="$TMP/src"
fi

echo "==> copying docs tree -> $DEST"
mkdir -p "$DEST"
cp -r "$SRC/website/docs/." "$DEST/"

COUNT="$(find "$DEST" -name '*.md' | wc -l)"
echo "    $COUNT markdown files, $(du -sh "$DEST" | cut -f1)"

echo
echo "==> (optional) local skills-index.json — replaces the blocked hub index"
if [[ -f "$SRC/scripts/build_skills_index.py" ]]; then
    ( cd "$SRC" && python3 scripts/build_skills_index.py 2>&1 | tail -3 ) \
        || echo "    (skipped: run scripts/build_skills_index.py manually to build a local hub index)"
else
    echo "    (skipped: builder not found in the checkout)"
fi

echo
echo "======================================================================"
echo "OK. Agent-facing markdown mirror: $DEST"
echo "    source: ${SRC}${TMP:+ (temporary clone)}"
echo
echo "Smoke test:"
echo "  search_files pattern='context_compression' path='$DEST'"
echo "  read_file    '$DEST/user-guide/configuration.md'"
echo
echo "Want to read the docs as a website? Use the checkout, not this script:"
echo "  cd ${SRC}/website && npm install && npm run start   # http://localhost:3000/docs/"
echo "======================================================================"
