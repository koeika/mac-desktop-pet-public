# Whisky&Cling

macOS 桌宠应用：自定义宠物素材、AI 编程进度提醒、背单词互动复习。

Native macOS desktop pet for AI coding progress and lightweight vocabulary review.
<img width="1630" height="1148" alt="image" src="https://github.com/user-attachments/assets/0e902a75-2f35-4d08-8f49-6de8cf759d7c" />
<img width="1371" height="1155" alt="image" src="https://github.com/user-attachments/assets/f053cd6f-9569-4189-bb4d-7e85eafff316" />

<img width="423" height="606" alt="image" src="https://github.com/user-attachments/assets/131bb611-00ee-496d-a1dc-08e99bab5e06" />
<img width="1314" height="926" alt="9686b2e1233161bdc30baf8abf9b1d45" src="https://github.com/user-attachments/assets/b5b69230-f3a6-4f5b-b7bb-f62a325e5770" />
<img width="322" height="530" alt="36ab8965642683cbd4829585ac859169" src="https://github.com/user-attachments/assets/12511adb-8d09-4870-9d50-87eb1df93301" />

## 功能概览

- 原生 macOS 桌宠：透明悬浮窗口、菜单栏控制、随机慢速走动、暂停、隐藏、锁定位置。
- 宠物素材管理：支持上传静态图片、GIF/APNG、MP4/MOV，也支持导入 Codex pet 包。
- 9 动作桌宠：Codex pet 包可使用 `idle`、`runningRight`、`runningLeft`、`waving`、`jumping`、`failed`、`waiting`、`running`、`review`。
- 照片伪动作：静态照片会用翻转、呼吸、弹跳、挥手、等待脉冲、失败抖动等程序化动作增强表现。
- 点击反馈：点击桌宠会随机说一句你配置的反馈词。
- AI 进度接入：通过 `petctl` CLI 或本地 HTTP API 上报 Codex、Claude Code、Cursor 等工具的工作进度。
- 词典学习：支持 CSV、JSON、可复制文本 PDF 导入；支持分类筛选、启用/禁用、删除、改名、统计。
- 学习节奏：可配置每天自动出现多少词、学习窗口时长、词汇气泡是否持续显示到反馈。
- 例句与音标补全：支持 OpenAI 或 DeepSeek key，批量补例句或音标。
- 本地优先：宠物素材和设置保存在本机，API key 存 macOS Keychain。

## 下载发布包

从 [GitHub Releases](https://github.com/koeika/mac-desktop-pet-public/releases) 下载最新的 `whiskycolin-<version>-macos-arm64.zip`。

解压后可以打开 `Whisky&Cling.app`。发布包做了 ad-hoc 签名，但尚未做 Apple Developer ID 公证；如果 macOS 提示来自未认证开发者，请右键 `Whisky&Cling.app`，选择 `打开`。

zip 内也包含 `bin/petctl`，可用于向运行中的桌宠上报 AI 进度。

## 从源码运行

```bash
git clone git@github.com:koeika/mac-desktop-pet-public.git
cd mac-desktop-pet-public
swift run whiskycolin
```

启动后会出现菜单栏应用 `Whisky&Cling`、透明桌宠窗口，以及配置中心。首次没有导入宠物时会自动打开配置中心。

最低目标系统：macOS 14+。

## 配置中心

从菜单栏 `Whisky&Cling` 打开 `打开配置中心...`。

### 宠物管理

这里是桌宠外观和行为的入口：

- `上传宠物素材（图片/GIF/视频）`：导入自己的宠物照片、动图或视频。
- `从 URL 安装`：粘贴 Codex pet 站点链接或直接 `.zip` 链接，先预览再安装。
- `导入本地已解压包`：导入包含 `pet.json` 和 `spritesheet.webp/png` 的宠物包文件夹。
- `移动速度`：调整桌宠走动速度，支持很慢的桌宠节奏。
- `点击反馈`：配置 3-5 条点击桌宠时随机出现的话。
- 宠物卡片：启用/禁用、出现权重、预览动作、删除素材。

Codex pet 包会复制到本 App 数据目录，并同步安装到 `~/.codex/pets/<pet-id>`，方便 Codex pet 生态继续使用。

### 词典学习

这里管理背单词内容：

- `导入 CSV/JSON 词典`：导入结构化词表。
- `导入 PDF 词典`：支持可选择文本 PDF；扫描版图片 PDF v1 不做 OCR。
- `学习节奏`：设置每天自动展示词数、学习窗口、气泡是否持续展示到反馈。
- `例句补充供应商`：保存 OpenAI 或 DeepSeek key，用于补例句、补音标。
- `分类筛选`：点击 `日语`、`英语`、`未分类` 等分类，只展示对应词典。
- 词典卡片：展示词数、分类、启用状态、已学/待加强/跳过统计，并支持编辑名称和删除。

CSV 字段：

```text
dictionaryName,term,reading,phonetic,meaning,example,hint,tags
```

只有 `term` 和 `meaning` 必填。`tags` 用 `|` 分隔多个标签。

PDF 导入是半自动流程：先抽取候选词条，展示可编辑预览，用户确认后才写入词典。

### AI 进度接入

这里用于让桌宠汇报 AI 工作状态：

- 查看本地服务状态和端口。
- 复制 `petctl progress`、`petctl done`、HTTP `curl` 示例。
- 点击 `发送测试进度` 验证桌宠气泡是否能收到事件。
- 选择只读状态日志文件，让桌宠监听明确授权的日志路径。

AI 进度优先级高于词汇气泡。收到 `done`、`failed`、`waiting` 等状态时会临时覆盖当前词汇卡片。

## 上报 AI 进度

普通终端 CLI 示例：

```bash
swift run petctl progress --source codex --stage "实现功能" --message "正在修改文件" --progress 60
swift run petctl done --source codex --stage "完成" --message "任务完成" --progress 100
swift run petctl message --source cursor --message "等待用户确认"
swift run petctl state
```

Codex 沙箱内建议优先用 HTTP API，避免 `swift run` 读取 SwiftPM manifest 或缓存时被权限拦截。

HTTP API：

```bash
curl --silent --show-error -X POST http://127.0.0.1:4789/v1/progress \
  -H 'content-type: application/json' \
  -d '{"source":"codex","stage":"验证","message":"正在运行测试","progress":80,"status":"review"}'
```

接口保持本地回环地址 `127.0.0.1`，默认不暴露到局域网。

## Codex 自动上报

仓库内提供两个模板：

- `AGENTS.codex-pet.md`：适合复制到自己的 Codex 指令中。
- `skills/codex-desktop-pet/SKILL.md`：适合安装为 Codex skill。

如果是从 GitHub Release 下载的 zip，解压后先运行：

```bash
./Scripts/install-codex-skill.sh
```

只打开 `Whisky&Cling.app` 不会让 Codex 自动上报。安装 skill 并重启 Codex 或开启新会话后，Codex 才会在进度节点和会话完成时主动通知桌宠。

默认使用本地 HTTP API，不需要配置本机源码路径。只有修改了端口时才需要设置环境变量：

```bash
export PET_SERVER_URL=http://127.0.0.1:4789
```

## 词汇反馈规则

- `认识啦`：标记为已学，降低后续出现频率。
- `不认识`：标记为待加强，提高后续出现频率，并关闭当前气泡。
- `先跳过`：降低后续出现频率。

自动词汇出现频率受 `每天自动展示词数` 和 `学习窗口` 控制；手动抽词不受每日自动上限限制。

## 数据与隐私

- 宠物素材、设置、词典数据保存在本机 Application Support 目录。
- OpenAI/DeepSeek key 存 macOS Keychain，不写入 `settings.json`。
- PDF 例句生成只发送词条、释义、读音/音标和少量上下文，不上传整本 PDF。
- iCloud Drive 同步只写学习记录文件，不依赖 Apple Developer 或 CloudKit。
- 本仓库不应包含本机绝对路径、API key、token、私有日志或个人文件。

## 测试

```bash
swift build
swift run codex-pet-selftest
```

自测覆盖词典解析、PDF 草稿、学习频率、状态事件、宠物选择、气泡策略和 key 不落盘等核心逻辑。

## 发布给别人使用

推送 `v*` tag 会触发 `.github/workflows/release.yml`，自动构建并发布 macOS zip 包。

```bash
git tag v0.1.0
git push origin v0.1.0
```

当前自动发布包包含 `.app` 和 `petctl`，但没有 Developer ID 公证。要做完全正常的双击安装体验，后续还需要 Apple Developer 账号、Developer ID 签名、公证和 DMG。

## 合法内容说明

完整词典和宠物素材请确保拥有使用和分发权限。仓库可以包含你自己整理并有权发布的词表；第三方教材、商业词典或素材包不建议直接公开提交。
