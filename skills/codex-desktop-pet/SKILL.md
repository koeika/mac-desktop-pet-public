---
name: codex-desktop-pet
description: Report Codex work progress to the local whiskycolin macOS desktop pet app.
---

Use this skill whenever the local whiskycolin/Codex Desktop Pet app should reflect Codex task progress.

Prefer the local HTTP API for routine Codex progress reporting. It avoids SwiftPM manifest and build-cache access, which can fail inside Codex's sandbox. Do not use `swift run` for routine reporting from Codex unless the HTTP API and a prebuilt `petctl` binary are unavailable.

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

If HTTP is unavailable but a release package is available, call its prebuilt `bin/petctl` directly. Avoid `swift run` inside Codex sandbox because it may fail while reading `Package.swift` or SwiftPM caches.

Before the final assistant message, call the `done` command after the work has actually completed. This dismisses any active vocabulary card and shows the completion bubble.

Keep messages short and phase-based.
