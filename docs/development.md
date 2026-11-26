# 开发与接入

普通用户请先阅读 [安装与使用指南](../README.md)。以下内容面向从源码运行或自行接入进度事件的开发者。

## 从源码运行

需要 macOS 14+ 与 Swift 命令行工具链。

```bash
git clone https://github.com/koeika/mac-desktop-pet-public.git
cd mac-desktop-pet-public
swift run PetPetKnows
```

`whiskycolin` 和 `CodexPetApp` 仍作为兼容入口保留。更名不改变旧版数据目录、Keychain 服务或应用 Bundle Identifier。

## 本地进度 API

App 默认只监听 `127.0.0.1:4789`。Codex 沙箱中优先使用 HTTP，避免 SwiftPM 缓存与 manifest 权限问题。

```bash
curl --silent --show-error -X POST http://127.0.0.1:4789/v1/progress \
  -H 'content-type: application/json' \
  -d '{"source":"codex","stage":"完成","message":"任务已完成","progress":100,"status":"done","threadId":"example-task"}'
```

保留 `POST /v1/progress`、`POST /v1/message`、`GET /v1/state`；CLI 保留 `petctl progress`、`done`、`message`、`state`。修改端口后可在 skill 环境中设置 `PET_SERVER_URL`。网页收藏接口需要本机配对凭证；不要公开端口或凭证。

## 验证与发布

```bash
swift build
swift run codex-pet-selftest
swift run PetPetKnows --self-test-notebook
swift run PetPetKnows --self-test-enrichment
bash Scripts/run-core-regression.sh
node --test ChromeExtension/tests/*.test.mjs
```

有完整 Xcode 时也应运行 `swift test`。`.github/workflows/release.yml` 提供带资源、插件和签名检查的发布流程；只有明确准备发布时才推送版本 tag。

正式数据保存在用户的 Application Support/CodexDesktopPet 目录。`WHISKYCLING_DATA_DIR` 与 `WHISKYCLING_PORT` 仅用于隔离开发/验收，配置中心会标注“演示数据”；不要把个人数据复制到截图或发布资源中。

`--export-user-guide` 使用生成的词条渲染使用指南配图，输出目录由 `WHISKYCLING_GUIDE_DIR` 指定。它不读取正式词库，配图生成后仍需人工检查内容、布局及隐私。
