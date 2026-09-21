#!/usr/bin/env python3
"""pin-auxiliary-providers.py — pin every auxiliary:* task to the main model/provider.

WHY: `auxiliary:*` blocks in config.yaml default to `provider: auto`, which resolves
independently of the main agent. On networks that block model providers (firewall 403),
an unpinned auxiliary call fails even though the main agent works — e.g. skill_view on a
bundled skill, web_extract summarisation, approval checks. Symptom: "Hi" works, tool
calls touching the skills hub 403.

Usage:
  pin-auxiliary-providers.py                # pin auxiliary:* to the main agent's provider/model
  pin-auxiliary-providers.py -p P -m M      # pin to explicit provider/model
  pin-auxiliary-providers.py --dry-run      # show what would change
  pin-auxiliary-providers.py --revert       # restore the .pre-airgap backup

Writes a backup at config.yaml.pre-airgap-pin before the first edit.
"""
import argparse, os, shutil, sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("pyyaml required (it ships with Hermes: use the Hermes venv's python3)")

ap = argparse.ArgumentParser()
ap.add_argument("--config", default=None, help="config.yaml path (default $HERMES_HOME/config.yaml)")
ap.add_argument("-p", "--provider", default=None)
ap.add_argument("-m", "--model", default=None)
ap.add_argument("--dry-run", action="store_true")
ap.add_argument("--revert", action="store_true")
a = ap.parse_args()

home = Path(os.environ["HERMES_HOME"]) if "HERMES_HOME" in os.environ else Path.home() / ".hermes"
cfg_path = Path(a.config) if a.config else home / "config.yaml"
if not cfg_path.exists():
    sys.exit(f"no config at {cfg_path}")
import os  # noqa: E402

backup = cfg_path.with_suffix(cfg_path.suffix + ".pre-airgap-pin")

if a.revert:
    if not backup.exists():
        sys.exit(f"no backup at {backup}")
    shutil.copy2(backup, cfg_path)
    print(f"reverted {cfg_path} from {backup}")
    sys.exit(0)

cfg = yaml.safe_load(cfg_path.read_text())

# resolve target provider/model: explicit args > the main agent's own settings
m = cfg.get("model") or {}
if isinstance(m, dict):
    provider = a.provider or m.get("provider")
    model = a.model or m.get("default") or m.get("model")
else:
    provider, model = a.provider, a.model
if not provider or not model or provider == "auto":
    sys.exit(
        "could not resolve a target: pass -p PROVIDER -m MODEL (the main agent's provider/model, "
        f"see `hermes model`), or set provider/model at the top of {cfg_path}"
    )

aux = cfg.get("auxiliary") or {}
if not aux:
    sys.exit("no auxiliary: block found in config — nothing to pin")

changed = []
for name, block in sorted(aux.items()):
    if not isinstance(block, dict):
        continue
    if block.get("provider") != provider or block.get("model") != model:
        changed.append(name)
        block["provider"] = provider
        block["model"] = model

if not changed:
    print(f"already pinned: all auxiliary tasks use {provider} / {model}")
    sys.exit(0)

print(f"auxiliary tasks to pin -> {provider} / {model}:")
for c in changed:
    print(f"  - {c}")
if a.dry_run:
    print("(dry run — nothing written)")
    sys.exit(0)

if not backup.exists():
    shutil.copy2(cfg_path, backup)
    print(f"backup: {backup}")
cfg_path.write_text(yaml.safe_dump(cfg, sort_keys=False))
print(f"written: {cfg_path}")
print("restart the gateway / new sessions pick this up; verify with: hermes dump | grep -A3 auxiliary")
