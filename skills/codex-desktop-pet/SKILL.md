---
name: codex-desktop-pet
description: Report Codex work progress to the local whiskycolin macOS desktop pet app.
---

Use this skill whenever the local whiskycolin/Codex Desktop Pet app should reflect Codex task progress.

Before using the commands, set `WHISKYCOLIN_REPO` to the local clone path of the macOS app repository:

```bash
export WHISKYCOLIN_REPO=/path/to/mac-desktop-pet
```

If `WHISKYCOLIN_REPO` is not set, replace `<path-to-mac-desktop-pet>` with your local clone path.
Do not commit real local absolute paths, API keys, source snippets, or full conversation text.

If the skill is available and the local app is running, report at least:

- task start or code-reading phase,
- implementation phase for non-trivial edits,
- verification phase when tests/checks run,
- final `done` event before the final user response,
- `failed` event if the task cannot be completed.

At meaningful milestones, call the local `petctl` CLI:

```bash
swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl progress --source codex --stage "读取代码" --message "正在梳理项目结构" --progress 20 --thread-id "${CODEX_THREAD_ID:-codex-session}"
swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl progress --source codex --stage "实现功能" --message "正在修改相关文件" --progress 60 --thread-id "${CODEX_THREAD_ID:-codex-session}"
swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl progress --source codex --stage "验证" --message "正在运行检查" --progress 85 --thread-id "${CODEX_THREAD_ID:-codex-session}"
swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl done --source codex --stage "完成" --message "任务完成" --progress 100 --thread-id "${CODEX_THREAD_ID:-codex-session}"
```

Before the final assistant message, call the `done` command after the work has actually completed. This dismisses any active vocabulary card and shows the completion bubble.

Keep messages short and phase-based.
