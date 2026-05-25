---
name: codex-desktop-pet
description: Report Codex work progress to the local Whisky&Cling macOS desktop pet app.
---

Use this skill whenever the local Whisky&Cling/Codex Desktop Pet app should reflect Codex task progress.

Use the local HTTP API for routine Codex progress reporting. It avoids SwiftPM manifest and build-cache access, which can fail inside Codex's sandbox. Do not invoke SwiftPM or any source-tree/release CLI for routine reporting unless the user explicitly asks to test the CLI.

When running inside Codex Desktop, the normal command sandbox may fail to reach `127.0.0.1` even while Whisky&Cling is listening. If a reporting `curl` fails with connection refused, timeout, or no visible desktop feedback, immediately retry the same local HTTP call with escalated command permissions. Do not treat the app as stopped until an escalated `GET /v1/state` also fails.

The app listens on `http://127.0.0.1:4789` by default. If the user changed the port, use `PET_SERVER_URL`, for example:

```bash
export PET_SERVER_URL=http://127.0.0.1:4789
```

Do not commit real local absolute paths, API keys, source snippets, or full conversation text.

If the skill is available and the local app is running, report at least:

- task start or code-reading phase,
- implementation phase for non-trivial edits,
- verification phase when tests/checks run,
- final `done` event before the final user response,
- `failed` event if the task cannot be completed.

At meaningful milestones, call the local HTTP API:

```bash
curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"读取代码\",\"message\":\"正在梳理项目结构\",\"progress\":20,\"status\":\"running\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"
curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"实现功能\",\"message\":\"正在修改相关文件\",\"progress\":60,\"status\":\"running\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"
curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"验证\",\"message\":\"正在运行检查\",\"progress\":85,\"status\":\"review\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"
curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"完成\",\"message\":\"任务完成\",\"progress\":100,\"status\":\"done\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"
```

If HTTP is unavailable even after an escalated retry, skip pet reporting and continue the user task. Do not fall back to any CLI automatically.

Before the final assistant message, call the `done` HTTP event after the work has actually completed. In Codex Desktop this call should use escalated command permissions when needed, so it dismisses any active vocabulary card and shows the completion bubble reliably.

Keep messages short and phase-based.
