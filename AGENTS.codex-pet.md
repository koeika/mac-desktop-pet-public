When working in Codex, report task progress to the local whiskycolin desktop pet app if it is available.

Set `WHISKYCOLIN_REPO` to the local clone path of this repository before using these commands.
If the variable is not set, replace `<path-to-mac-desktop-pet>` with your own local path.
Do not commit a real local absolute path to a public repository.

- Use `swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl progress --source codex --stage "读取代码" --message "正在梳理项目结构" --progress 20 --thread-id "${CODEX_THREAD_ID:-codex-session}"` near the start of non-trivial work.
- Use `swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl progress --source codex --stage "实现功能" --message "正在修改相关文件" --progress 60 --thread-id "${CODEX_THREAD_ID:-codex-session}"` while implementing.
- Use `swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl progress --source codex --stage "验证" --message "正在运行检查" --progress 85 --thread-id "${CODEX_THREAD_ID:-codex-session}"` while verifying.
- Before the final response after successful work, run `swift run --package-path "${WHISKYCOLIN_REPO:-<path-to-mac-desktop-pet>}" petctl done --source codex --stage "完成" --message "任务完成" --progress 100 --thread-id "${CODEX_THREAD_ID:-codex-session}"`.
- If the task fails or is blocked, report `petctl progress --status failed` with a short reason.

If the local app or server is unavailable, continue normally and do not block the user task.
