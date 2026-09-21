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
| `--build-site` | Also build the rendered Docusaurus site for humans → `${DEST}-site`. Runs `npm install/build` inside `<src>/website`, creating `node_modules/` and `build/` there. |
| `--locale L` | With `--build-site`: build only this locale. **Default `en`.** Upstream ships `en`, `zh-Hans`, `ko`; each is a full extra build, so `en` is ~3× faster and a third of the output. `--locale all` reproduces the upstream 3-locale site. |
| `--base-url P` | With `--build-site`: build the site for URL prefix `P` (default: upstream `/docs/`). Use `/` to serve at the root of an internal host. |
| `-h`, `--help` | Usage. |

Env: `DEST` — mirror root (default `/opt/data/docs/hermes`); `HERMES_SRC` — env equivalent of `--src`.

Output: ~330 markdown files (~5.5 MB) that the agent reads with `read_file` / `search_files`, plus
optionally the static site to serve on an internal hostname.

### Serving the built site: mind the `/docs/` prefix

Upstream is authored *for* a `/docs/` prefix — `baseUrl: '/docs/'`, `routeBasePath: '/'`, and **883
hardcoded `](/docs/…` links across 161 doc files**. So there are exactly two consistent setups:

| Want | Do |
|---|---|
| Serve under `/docs/` | Build normally (no `--base-url`) and mount it there: `location /docs/ { alias /srv/hermes-docs/; }`. All assets, links and search work as-built. |
| Serve at `/` | `--build-site --base-url /`. This rebuilds in a throwaway copy **and rewrites those 883 links** so navigation doesn't 404. |

Flipping `baseUrl` without the link rewrite gives you a site that loads an empty shell: `/` returns 200
while every `/assets/…` request 404s. That's the trap `--base-url` exists to close.

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
