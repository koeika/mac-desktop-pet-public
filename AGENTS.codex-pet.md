When working in Codex, report task progress to the local Whisky&Cling desktop pet app if it is available.

Prefer the local HTTP API. It avoids SwiftPM manifest and build-cache access, which can fail inside Codex's sandbox. Do not use `swift run` for routine progress reporting unless HTTP and a prebuilt `petctl` binary are unavailable.

Use `PET_SERVER_URL` only if the user changed the default port:

```bash
export PET_SERVER_URL=http://127.0.0.1:4789
```

- Near the start of non-trivial work, run `curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"读取代码\",\"message\":\"正在梳理项目结构\",\"progress\":20,\"status\":\"running\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"`.
- While implementing, run `curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"实现功能\",\"message\":\"正在修改相关文件\",\"progress\":60,\"status\":\"running\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"`.
- While verifying, run `curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"验证\",\"message\":\"正在运行检查\",\"progress\":85,\"status\":\"review\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"`.
- Before the final response after successful work, run `curl --silent --show-error -X POST "${PET_SERVER_URL:-http://127.0.0.1:4789}/v1/progress" -H "content-type: application/json" -d "{\"source\":\"codex\",\"stage\":\"完成\",\"message\":\"任务完成\",\"progress\":100,\"status\":\"done\",\"threadId\":\"${CODEX_THREAD_ID:-codex-session}\"}"`.
- If the task fails or is blocked, report `status:"failed"` with a short reason.

If the local app or server is unavailable, continue normally and do not block the user task.
