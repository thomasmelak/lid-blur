# Repository rules

These rules apply to every change made in this repository.

## Attribution

- Never add AI or tool attribution anywhere: not in code, comments, commit messages, PR titles, PR descriptions, or documentation.
- Commits must not contain `Co-Authored-By`, `Claude-Session`, or similar trailers.
- PR descriptions must not contain a "Generated with Claude Code" footer or session links. If a tool appends one, edit the PR body immediately after creating it and re-read it to confirm it is gone.

## Commits

- Commit only as the repository owner: `Thomas Melak <me@thomasmelak.io>`. Set `git config user.name` and `user.email` before committing.
- Never commit or push to `main`.
- Work on a feature branch named after the task or phase (for example `feature/landing-page`), then open a pull request for the owner to review and merge.

## Pull requests

- Keep descriptions professional and concise, written for an engineer, using these sections: Summary, Changes, Testing.
- Do not include guides, setup steps, or "before/after merging" instructions for the owner in a PR. Report those directly to the owner instead.
