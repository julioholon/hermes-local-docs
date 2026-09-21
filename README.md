# hermes-local-docs

Hermes Agent skill: read the Hermes documentation from a **local offline mirror** instead of
`hermes-agent.nousresearch.com`.

Built for networks that classify outbound traffic by **domain category** — where GitHub, npm and PyPI
work fine, but `*.nousresearch.com` lands in an "AI-related" bucket and 403s. The bundled
`hermes-agent` skill links to that docs host in ~16 places, so the agent breaks every time it tries to
consult it. This skill points the agent at a mirrored copy on disk and forbids it from going to the
network for docs.

## Install

Add the repo as a tap, then install the skill — the identifier is **`owner/repo/skill-name`**:

```bash
hermes skills tap add julioholon/hermes-local-docs
hermes skills install julioholon/hermes-local-docs/hermes-docs-local
```

Or install it straight from GitHub with no tap (note the full path, since the skill is not at the
repo root):

```bash
hermes skills install julioholon/hermes-local-docs/skills/hermes-docs-local
```

Both pull `SKILL.md` plus its `scripts/` directory. A bare `hermes skills install hermes-docs-local`
will **not** resolve — it fails with *"No skill named 'hermes-docs-local' found in any source"*.

Install runs the skills security scanner first. Expect two `MEDIUM supply_chain` advisories against
the mirror script (`git_clone`, `unpinned_npm_install`) — both are inherent to the job it does, and the
verdict is `SAFE`/`ALLOWED`.

## Build the mirror it reads

The skill is inert until there is something at the mirror root (`/opt/data/docs/hermes`, override with
`HERMES_DOCS_MIRROR`). The script ships inside the skill:

```bash
SKILL_DIR=$(dirname "$(find "${HERMES_HOME:-$HOME/.hermes}/skills" \
    -path '*/hermes-docs-local/SKILL.md' 2>/dev/null | head -1)")

# already have a hermes-agent checkout? use it — no clone, no download:
bash "$SKILL_DIR/scripts/hermes-docs-mirror.sh" --src ~/src/hermes-agent

# otherwise it sparse-clones into a temp dir:
bash "$SKILL_DIR/scripts/hermes-docs-mirror.sh"
```

| Flag | Effect |
|---|---|
| `--src PATH` | Use an existing `hermes-agent` checkout instead of cloning one into `/tmp`. No network access at all in this mode; validated to contain `website/docs/`. |
| `--pull` | With `--src`: `git pull --ff-only` the checkout first so the mirror is fresh. A diverged/dirty/offline clone only warns. |
| `-h`, `--help` | Usage. |

Env: `DEST` — mirror root (default `/opt/data/docs/hermes`); `HERMES_SRC` — env equivalent of `--src`.

Output: ~330 markdown files (~5.5 MB) that the agent reads with `read_file` / `search_files`. That's
all this script does — it never builds or serves the website.

### Browsing the docs as a website? Don't use this script

No build step is needed. In a checkout, the Docusaurus dev server serves the site immediately and
honours the upstream `baseUrl`, so every link and asset resolves:

```bash
cd <clone>/website
npm install
npm run start          # http://localhost:3000/docs/
```

For a static copy to host on nginx/caddy, build there (`npm run build && npm run serve`) and **mount
it under `/docs/`** — `location /docs/ { alias <website>/build/; }`. The source is authored for that
prefix (`baseUrl: '/docs/'`, `routeBasePath: '/'`, ~880 absolute `/docs/…` links), so serving the
build at a host root would need those links rewritten. Just mount it at `/docs/` instead.

### The 403 can still happen without the guard

Installing this skill helps only when it's *in context*. The bundled `hermes-agent` skill carries 16+
direct `hermes-agent.nousresearch.com` links; an agent that loaded `hermes-agent` but not
`hermes-docs-local` will still follow them and eat the firewall 403. The fix is a **pre_tool_call
shell hook** that blocks the call at tool level and returns the mirror path as the error message —
so the agent self-corrects no matter which skill it loaded:

```bash
"$HERMES_HOME/skills/hermes-docs-local/scripts/install-airgap-guard.sh"
```

It installs `airgap-guard.sh` into `$HERMES_HOME/agent-hooks/` and registers it in `config.yaml`
(never edits an existing `hooks:` block — prints merge lines instead). Set `HERMES_DOCS_MIRROR` to
override the mirror path, `HERMES_AIRGAP_GUARD=0` to disable for a session. Note the consent model:
Hermes prompts once per (event, command) pair — for headless/gateway use set
`hooks_auto_accept: true`.

## Layout

```
skills/
└── hermes-docs-local/
    ├── SKILL.md                     # the skill: hard no-network rule, section map, URL → local path table
    └── scripts/
        └── hermes-docs-mirror.sh     # sparse-clone OR --src copy → markdown mirror (+ optional site build)
```

## Notes

- The mirror is **additive**: pages removed upstream stay behind. Delete `$DEST` and re-run for an exact
  copy.
- No credentials, no API keys, no phone-home: `--src` mode is entirely offline.
- MIT licensed.

## License

MIT — see [LICENSE](LICENSE).
