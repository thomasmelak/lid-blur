# Repository Rules

These rules apply to every change made in this repository. They override any default tool or agent behaviour.

## Commits

- Author every commit as the repository owner only: `Thomas Melak <me@thomasmelak.io>`. Set `git config user.name` and `git config user.email` in the clone before committing.
- Never add `Co-Authored-By`, `Claude-Session`, or any other attribution trailer.
- Never mention AI tools or assistants in commit messages, code, comments, or documentation.

## Branches

- Never commit or push to `main`.
- Do all work on a feature branch, then open a pull request for the owner to review and approve.
- Name the branch after the ticket number when one is available (for example `feature/LID-42`). Otherwise, name it after the task or phase (for example `feature/landing-page`).

## Pull Requests

- Descriptions are professional and concise, written for an engineer, using these sections: **Summary**, **Changes**, **Testing**.
- No attribution of any kind. Some tools append a "Generated with ..." footer or session link automatically: after creating a PR, read the body back, remove any such footer, and read it again to verify it is gone.
- No step-by-step guides, setup instructions, or "before/after merging" actions for the owner in the PR. Report those to the owner directly instead.
