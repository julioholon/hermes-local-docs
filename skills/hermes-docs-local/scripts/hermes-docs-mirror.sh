#!/usr/bin/env bash
# hermes-docs-mirror.sh — make the Hermes docs available offline on a locked-down network.
#
# WHY: the bundled `hermes-agent` skill links to https://hermes-agent.nousresearch.com/docs/*.
# Networks that classify by DOMAIN CATEGORY block that host as "AI-related", so it 403s and the
# agent fails whenever it tries to consult the docs.
#
# Usually only AI/model providers are blocked. npm, PyPI and GitHub keep working, so BOTH delivery
# modes below are available:
#
#   (A) markdown mirror -> for the AGENT  (read_file / search_files; fastest, no HTML parsing)
#   (B) built site      -> for HUMANS + clickable links (Docusaurus build, served internally)
#
# Usage:
#   ./hermes-docs-mirror.sh                            # (A) markdown mirror (fresh /tmp clone)
#   ./hermes-docs-mirror.sh --src ~/src/hermes-agent    # (A) from an EXISTING clone (no download)
#   ./hermes-docs-mirror.sh --src ~/src/hermes-agent --pull   # update that clone first, then copy
#   ./hermes-docs-mirror.sh --build-site               # (A) + (B)
#   ./hermes-docs-mirror.sh --src ... --build-site     # both, from an existing clone
#   ./hermes-docs-mirror.sh --build-site --base-url /  # rebuild the site to serve at the ROOT
#   ./hermes-docs-mirror.sh --build-site --locale all  # build every upstream locale
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
#   --build-site  Also build the Docusaurus site -> ${DEST}-site.
#   --locale L    With --build-site: build only this locale (default: en). Upstream ships en,
#                 zh-Hans and ko; each locale is a full extra build, so 'en' is ~3x faster and
#                 a third of the output size. Use 'all' to reproduce the upstream 3-locale site.
#   --base-url P  With --build-site: build the site for this URL prefix (default: the upstream
#                 '/docs/'). Use '/' to serve it at the root of an internal hostname. Builds in a
#                 throwaway copy and rewrites the docs' own absolute /docs/ links, because the
#                 source is authored against a /docs/ prefix — flipping the baseUrl alone yields
#                 a site whose every internal link 404s.
#                 NOTE: the build runs npm install/build inside <src>/website, which creates
#                 node_modules/ and build/ in that checkout.
#   -h, --help    Show this help.
#
# Env: DEST (default /opt/data/docs/hermes), HERMES_SRC (default of --src).

set -euo pipefail

DEST="${DEST:-/opt/data/docs/hermes}"
SRC="${HERMES_SRC:-}"
BUILD_SITE=0
PULL=0
BASE_URL=""
LOCALE="en"

usage() { sed -n '/^# Usage:/,/^# Env:/p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)     [[ $# -ge 2 ]] || { echo "ERROR: --src needs a path" >&2; exit 2; }
                   SRC="$2"; shift 2 ;;
        --src=*)   SRC="${1#*=}"; shift ;;
        --pull)    PULL=1; shift ;;
        --build-site) BUILD_SITE=1; shift ;;
        --locale) [[ $# -ge 2 ]] || { echo "ERROR: --locale needs a value" >&2; exit 2; }
                  LOCALE="$2"; shift 2 ;;
        --locale=*) LOCALE="${1#*=}"; shift ;;
        --base-url) [[ $# -ge 2 ]] || { echo "ERROR: --base-url needs a path" >&2; exit 2; }
                    BASE_URL="$2"; shift 2 ;;
        --base-url=*) BASE_URL="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "ERROR: unknown argument: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    esac
done

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
    echo "==> (A) fetching docs source (sparse, depth=1) -> $TMP/src"
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

if [[ "$BUILD_SITE" == "1" ]]; then
    if [[ "$LOCALE" != "all" ]] && ! [[ "$LOCALE" =~ ^[A-Za-z0-9-]+$ ]]; then
        echo "ERROR: --locale must be a locale code (en, zh-Hans, ko) or 'all'" >&2
        exit 2
    fi
    LOCALE_ARG=""
    [[ "$LOCALE" != "all" ]] && LOCALE_ARG="--locale $LOCALE"
    echo
    echo "==> (B) building the Docusaurus site (npm is usually reachable on such networks)"
    echo "    locale: $LOCALE"
    if [[ -z "$TMP" ]]; then
        echo "    (using the existing checkout's website/ tree)"
    else
        git -C "$SRC" sparse-checkout add website
    fi

    if [[ -n "$BASE_URL" ]]; then
        # Normalise + validate: the value is injected into a TS string literal and a sed script.
        [[ "$BASE_URL" == /* ]] || BASE_URL="/$BASE_URL"
        [[ "$BASE_URL" == */ ]] || BASE_URL="$BASE_URL/"
        if ! [[ "$BASE_URL" =~ ^/[A-Za-z0-9._/-]*$ ]]; then
            echo "ERROR: --base-url must be a URL path like '/' or '/hermes/'" >&2
            exit 2
        fi
        # Build in a throwaway copy so the checkout is never modified.
        [[ -n "$TMP" ]] || TMP="$(mktemp -d)"
        CP="$TMP/site"
        mkdir -p "$CP"
        echo "    baseUrl override -> $BASE_URL (building in a throwaway copy)"
        tar -C "$SRC/website" -cf - --exclude=node_modules --exclude=build --exclude=.docusaurus . \
            | tar -C "$CP" -xf -
        # The docs link to each other as ](/docs/... — rewrite those or every internal link 404s.
        LINKED="$(grep -rl '](/docs/' "$CP/docs" 2>/dev/null | wc -l | tr -d ' ')"
        find "$CP/docs" -type f \( -name '*.md' -o -name '*.mdx' \) \
            -exec sed -i "s#](/docs/#]($BASE_URL#g" {} +
        echo "    rewrote absolute /docs/ links in $LINKED doc files"
        cat > "$CP/docusaurus.config.local-mirror.ts" <<EOF
import type {Config} from '@docusaurus/types';
import base from './docusaurus.config';

export default {...base, baseUrl: '$BASE_URL'} as Config;
EOF
        if [[ -d "$SRC/website/node_modules" ]]; then
            ln -s "$SRC/website/node_modules" "$CP/node_modules"
        else
            ( cd "$CP" && npm install )
        fi
        ( cd "$CP" && npm run build -- --config docusaurus.config.local-mirror.ts $LOCALE_ARG )
        BUILT="$CP/build"
    else
        ( cd "$SRC/website" && npm install && npm run build -- $LOCALE_ARG )
        BUILT="$SRC/website/build"
    fi

    OUT="${DEST}-site"
    mkdir -p "$OUT"
    cp -r "$BUILT/." "$OUT/"
    echo "    static site -> $OUT ($(du -sh "$OUT" | cut -f1))"
    echo
    echo "    Serve it internally, e.g.:"
    if [[ -n "$BASE_URL" && "$BASE_URL" != "/docs/" ]]; then
        echo "      python3 -m http.server 8080 --directory $OUT   # links expect $BASE_URL"
    else
        echo "      # the site is built for a /docs/ prefix — mount it there, e.g. nginx:"
        echo "      #   location /docs/ { alias $OUT/; }"
        echo "      # serving it at the root instead needs --base-url /"
    fi
    echo "    then front it with nginx/caddy, give it an internal hostname,"
    echo "    and repoint the skill URLs at that hostname."
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
echo "Sections:"
find "$DEST" -maxdepth 2 -type d | sed "s|$DEST|  |" | sort | head -20
echo "======================================================================"
