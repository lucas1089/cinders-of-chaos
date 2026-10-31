# Game Studios agents and skills

Vendored from https://github.com/Donchitos/claude-code-game-studios.
Commit: 05ad7c8a5b8aa2aa86bbd3439ae7cf7295cac418. MIT license: `GAME_STUDIOS_LICENSE.md`.

## What is here

- `agents/`: 49 subagents.
- `skills/`: 74 skills.
- `docs/`: references and templates the skills read.
- `scripts/`: helper scripts the skills run.
- `hooks/yaml-helper.sh`: config reader the skills call.
- `hooks/update-check.sh`: kept only as a version source. `scripts/set-stage.sh` reads its version line.

No hook is registered. `settings.json` is ours and unchanged.

## Left out

- Their `settings.json`. Its hooks and deny rules would block our workflow. We force-push the dev branch after merges.
- All other hooks. We do not want them firing.
- `rules/`, `statusline.sh`, their `CLAUDE.md`, `project.yaml`.
- Some skills and docs still name `rules/` files. Those links are dead. Ignore them.

## Local changes

Example names of commercial games were replaced with genre descriptions.
Project rule: no names of other games in the repo. `tools/ci/check_names.py` checks part of it.
Keep that rule when updating from upstream. Scan the new text again.

## Config

Skills read `project.yaml` and `project.local.yaml` at the repo root.
Neither file exists here. Skills then fall back to defaults.
Check: `bash .claude/hooks/yaml-helper.sh resolve_config --keys review_mode,automation,docs.density,workflow`.

## Cautions

- Some skill names may shadow built-in or plugin commands: `code-review`, `security-audit`, `brainstorm`, `help`, `settings`.
- `/setup-engine` writes an engine stack into `CLAUDE.md`. This project has no engine in their sense. Do not run it.
- Many skills assume their folder layout: `design/gdd/`, `production/`, `src/`. Ours differs. Read output with care.
- Our `CLAUDE.md` rules win over anything these files say.
