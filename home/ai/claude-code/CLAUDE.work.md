# Work Profile Overlay

Loaded only on the work machine (`osConfig.profile == "work"`). Nix symlinks
this file to `~/.claude/CLAUDE.profile.md`, which `CLAUDE.global.md` imports.

Put **machine-bound** guidance here — things tied to this machine's tools,
credentials, or secrets (work Slack conventions, AWS/k8s context defaults,
analytics MCP usage). Do **not** put repo-keyed workflow rules here: the
Linear-vs-GitHub-issue decision is keyed on the repo's GitHub org, not the
machine, so it stays in `CLAUDE.global.md` (a work laptop can clone a personal
repo and vice versa).

<!-- nothing here yet — fill in as work-specific needs surface -->
