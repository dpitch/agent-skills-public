# Rules for cloud coding agents

## Language
- Reply in French. Code, commits, branch names and technical terms stay in English.

## Git
- Work on your own branch, commit and push it before you finish.
- Never push to `main`, merge, force-push or delete branches unless the task says so explicitly.
- If the task gives an expected base SHA, check `git rev-parse HEAD` first and stop if it differs.

## Safety
- Never send anything to a person: no message, email, social post, publication or production deploy.
- Never spend money (paid APIs, credits) unless the task says so.
- Never print, copy or commit the content of `.env` files, tokens or keys.

## How to work
- Investigate before fixing: find the cause, fix it, then prove it (run the tests or the command that shows it works).
- Stay in scope. If the task needs something this sandbox cannot do (iOS simulator, a desktop app, a logged-in browser), stop and say so.
- Use the installed skills when they fit the task (for example `tdd`, `diagnosing-bugs`, the `principle-*` skills, `impeccable` for UI).
- UI: never a colored side stripe (`border-left`/`border-right`) on cards, list items, callouts or alerts.
