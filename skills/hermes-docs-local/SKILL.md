---
name: hermes-docs-local
description: "Use when a network blocks hermes-agent.nousresearch.com, or whenever the hermes-agent skill would send you to those docs. Serves the Hermes docs from a local offline mirror instead of the network."
version: 1.0.1
author: julioholon
metadata:
  hermes:
    tags: [hermes, docs, offline, airgapped, firewall, mirror]
---

# Hermes Docs — Local Offline Mirror

## Why this exists

Many corporate networks classify by **domain category**, not by path: `*.nousresearch.com` lands in
an "AI-related" bucket and gets 403'd (returned as an HTML page, which surfaces as
`Streaming failed before delivery` in `errors.log`). The bundled `hermes-agent` skill links to that
host in ~16 places, so the agent fails every time it tries to consult the docs.

GitHub and npm are usually *not* blocked (blocking them breaks legitimate business traffic), so the
fix is to materialize the docs locally once and read them from disk.

## Hard rule

**Never fetch `hermes-agent.nousresearch.com` in a locked-down environment.** Do not read it through
a text-extraction proxy either — the block is a deny rule, not a rendering problem. Resolve every doc
link against the local mirror below, and **cite the local path you read**, not a URL.

## Where the docs are

Default mirror root:

```
/opt/data/docs/hermes
```

Override with `HERMES_DOCS_MIRROR` if your layout differs. If that path is empty, **say so** — build
it with the script below, or ask the user where the mirror lives. Do not fall back to the network, and
never invent doc content to fill a gap.

## How to read it

The mirror is plain markdown (~330 files) — no server, no HTML. Use the file tools:

```
search_files(pattern="context_compression", path="/opt/data/docs/hermes")
search_files(pattern="provider.*base_url", path="/opt/data/docs/hermes", file_glob="*.md")
read_file("/opt/data/docs/hermes/user-guide/configuration.md")
```

Prefer `search_files` first to locate the page, then `read_file` for the full content.

## Section map

| Topic | Path under the mirror root |
|---|---|
| Configuration, providers, agent behaviour | `user-guide/configuration.md` |
| Features (cron, memory, MCP, hooks, kanban…) | `user-guide/features/` |
| Messaging platforms (Telegram, Slack, Discord…) | `user-guide/messaging/` |
| Profiles, sessions, gateway usage | `user-guide/` |
| Bundled + optional skill catalog | `user-guide/skills/` |
| CLI commands, env vars, slash commands, tools | `reference/` |
| Architecture, contributing, tool authoring | `developer-guide/` |
| Tutorials and end-to-end walkthroughs | `guides/` |
| Install / first run | `getting-started/` |

## Known URL → local path equivalents

- `https://hermes-agent.nousresearch.com/docs/` → `index.md`
- `.../docs/user-guide/configuration` → `user-guide/configuration.md`
- `.../docs/reference/cli-commands` → `reference/cli-commands.md`
- `.../docs/reference/environment-variables` → `reference/environment-variables.md`
- `.../docs/reference/slash-commands` → `reference/slash-commands.md`
- `.../docs/reference/tools-reference` → `reference/tools-reference.md`
- `.../docs/integrations/providers` → `integrations/providers.md`
- `.../docs/user-guide/features/cron` → `user-guide/features/cron.md`
- `.../docs/user-guide/features/mcp` → `user-guide/features/mcp.md`
- `.../docs/user-guide/features/memory` → `user-guide/features/memory.md`
- `.../docs/user-guide/messaging/` → `user-guide/messaging/`
- `.../docs/user-guide/profiles` → `user-guide/profiles.md`

## Hard rule, enforced

Relying on this skill being in context is not enough: the agent can follow a `hermes-agent.nousresearch.com`
link from the bundled `hermes-agent` skill without ever loading this one. The companion hook
(`scripts/install-airgap-guard.sh`) blocks such tool calls and returns the mirror path as the error
message. If a fetch to that host was blocked, that is the expected behaviour — never retry the call.

## Building / refreshing the mirror

The script ships with this skill (`scripts/hermes-docs-mirror.sh`). Resolve it relative to the
installed `SKILL.md`, never from a hardcoded path:

```bash
SKILL_DIR=$(dirname "$(find "${HERMES_HOME:-$HOME/.hermes}/skills" \
    -path '*/hermes-docs-local/SKILL.md' 2>/dev/null | head -1)")

# already have a hermes-agent checkout? use it — no clone, no download:
bash "$SKILL_DIR/scripts/hermes-docs-mirror.sh" --src ~/src/hermes-agent

# otherwise it sparse-clones into a temp dir (needs github.com reachable):
bash "$SKILL_DIR/scripts/hermes-docs-mirror.sh"
```

Options:

| Flag | Effect |
|---|---|
| `--src PATH` | Use an existing `hermes-agent` checkout instead of cloning. No network access at all. Validated to contain `website/docs/`. |
| `--pull` | With `--src`: `git pull --ff-only` first so the mirror is fresh; a failure only warns. |
| `-h`, `--help` | Usage. |

Env: `DEST` (mirror root, default `/opt/data/docs/hermes`), `HERMES_SRC` (default of `--src`).

## If a rendered site is served internally

Some deployments also serve the site on an internal hostname. Links *may* be followed **only** against
that internal host — never against `hermes-agent.nousresearch.com`. When in doubt, prefer the markdown
mirror.

To browse the docs as a website on a machine that has a checkout, the dev server needs no build:

```bash
cd <clone>/website && npm install && npm run start   # http://localhost:3000/docs/
```
