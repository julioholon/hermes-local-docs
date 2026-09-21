# hermes-local-docs

Hermes Agent skill: read the Hermes documentation from a **local offline mirror** instead of
`hermes-agent.nousresearch.com`.

Built for networks that classify outbound traffic by **domain category** — where GitHub, npm and PyPI
work fine, but `*.nousresearch.com` lands in an "AI-related" bucket and 403s. The bundled
`hermes-agent` skill links to that docs host in ~16 places, so the agent breaks every time it tries to
consult it. This skill points the agent at a mirrored copy on disk and forbids it from going to the
network for docs.

## Install

```bash
hermes skills tap add julioholon/hermes-local-docs
hermes skills install hermes-docs-local
```

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
| `-h`, `--help` | Usage. |

Env: `DEST` — mirror root (default `/opt/data/docs/hermes`); `HERMES_SRC` — env equivalent of `--src`.

Output: ~330 markdown files (~5.5 MB) that the agent reads with `read_file` / `search_files`, plus
optionally the static site to serve on an internal hostname.

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
