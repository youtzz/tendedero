# tendedero（CleanShot X 魔改版）

本仓库是 [alejandrobujan/tendedero](https://github.com/alejandrobujan/tendedero) 的**个人魔改 fork**——一个 macOS 菜单栏截图晾衣绳 App，特色是与 CleanShot X 深度联动。源码公开（[youtzz/tendedero](https://github.com/youtzz/tendedero)），供自行编译使用；不发布二进制，非官方。

**背景**：上游没有「第三方截图工具只截图不保存也上绳」的能力（其 PR #60 只做了 QQ 截图例外、且未合并），故此 fork 自用。

## 分支与提交约定

- 本地分支：`local-cleanshot`，**全部魔改压在一条 commit 上**（rebase 友好，同步上游的前提）
- 基线：上游 `v1.5.0` tag
- 远程：`origin` = 上游（只读，永不 push）；`mine` = 自己的公开 fork（`youtzz/tendedero`）
- 推送：`git push mine local-cleanshot`；同步上游 rebase 后历史被重写，用 `git push mine local-cleanshot --force-with-lease`
- 改动继续追加时保持单条 commit（rebase 时解决冲突即可）

## 本地魔改点（5 项）

1. **CleanShot 剪贴板联动**（截图「不保存」也上绳）：CleanShot 每次截图都会复制「图片 + 媒体库文件 URL」；新增 `CleanShotCapture.swift` 识别该精确特征放行，`ClipboardWatcher.swift` 为其开独立通道（与「挂上复制的图片」互不相干，普通复制的图片不受影响）。开关：菜单「CleanShot 截图 → 接管 CleanShot 截图」（defaults key `cleanShotClipboardEnabled`）。
2. **委托 CleanShot 原生功能**：右键菜单「CleanShot ▸」= 在 CleanShot 中编辑（`open-annotate`）/ 在 CleanShot 中钉住（`pin`）/ 发送到 CleanShot 浮窗（`add-quick-access-overlay`）；经 `CleanShotTools.swift` 走 CleanShot 的 URL scheme。
3. **hover 按钮组**：悬停卡片显示 ✕（收件箱文件=进废纸篓 / 其它来源=只下线）、📌 pin、✎ 编辑、Copy/Save 居中 pill（Save=收件箱文件存到桌面）；实现在 `GrabArea.swift` 的 `GrabView`（AppKit 绘制+命中；`verifyHover` 每 0.25s 自检兜底，防面板忽略鼠标事件时悬停留存）。录像只显示 ✕/Copy/Save。
4. **复制即下线 + 单击延迟**：任何复制动作（单击 / Copy 按钮 / 菜单）后约 0.6 秒自动下线；收件箱文件随之进废纸篓（CleanShot 媒体库有底档），其它来源只下线不删文件。实现在 `Line.copy`。单击（含悬停 Copy/Save 胶囊）延迟到系统双击间隔（`NSEvent.doubleClickInterval`）后再执行，好让双击打开预览时不会先复制、先下线；双击一律打开预览。实现在 `GrabArea.swift` 的 `GrabView`。
5. **往下滚扔卡**：指针悬停在卡片上、向下累计拉动约 36pt（滚轮约 2–3 格），卡片按 ✕ 同款方式扔下线（收件箱进废纸篓），走坠落动画；没拉够无事、惯性（momentum）不接力。卡片上「往下滚」专属这个手势，不再横向浏览老卡片（浏览保留：往上滚 / 触控板左右滑 / 长线空隙处滚）。实现在 `AppDelegate.swift` 的 `scrollThrows`。

## 使用前提

- CleanShot 的 after-capture 保持勾选「**Copy file to clipboard**」（截图才会产生剪贴板事件）
- 首次从菜单调 CleanShot 功能时可能弹一次 URL scheme 授权，点允许

## 构建 / 安装

```sh
bash scripts/build-app.sh
# 退出 Tendedero 后：
ditto build/Tendedero.app /Applications/Tendedero.app
```

- 双架构（arm64 + x86_64）、ad-hoc 签名；**每次重编译 macOS 可能重新弹「桌面文件夹访问」**，点允许
- 版本号自动跟随 git tag（`build-app.sh`）
- 官方版备份：`backup/Tendedero-1.5.0-official.app`（还原 = 反向 ditto 回 /Applications；`backup/` 已在 .gitignore）
- ⚠️ **别跑 `brew upgrade --cask tendedero`**（会盖回官方版；跑错重跑同步脚本即可恢复）

## 同步上游

```sh
bash scripts/sync-upstream.sh      # fetch → rebase 到最新 tag → 编译 → 安装 → 重启
```

- 冲突预期点：`AppDelegate.swift`（菜单）、`GrabArea.swift` / `ClipboardWatcher.swift`（钩子）、`en/zh-Hans.lproj`；脚本冲突时会停下给指引
- 只想编译不安装：`bash scripts/sync-upstream.sh --build-only`

## 冒烟清单（改完 / 同步后跑一遍）

1. CleanShot 截一张（**不保存**）→ 秒上绳
2. hover 卡片：✕/📌/✎/Copy/Save 出现；鼠标移开即消失（不留存）
3. 📌 / ✎ 唤起 CleanShot 原生 pin 浮窗 / 编辑面板
4. 点复制 → 约 0.5 秒后 Copied 徽标出现、再 0.6 秒自动下线（收件箱文件进废纸篓）；双击卡片（包括中央 pill 上）→ 只打开预览，不复制、不下线
5. 悬停卡片往下滚（累计约 36pt）→ 卡片坠落下线；没拉够 → 无事发生
