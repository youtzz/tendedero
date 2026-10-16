# tendedero（CleanShot X 魔改版）

每一张截图都先挂在屏幕上方那条晾衣绳上。把指针停在菜单栏，绳子滑下来；移开，它就收回去。

macOS 14 以上，免费开源。改自 [Tendedero](https://github.com/alejandrobujan/tendedero) 1.5.0，MIT 授权。

这是**个人魔改 fork**，特色是**与 CleanShot X 深度联动**：用 CleanShot X 截图（哪怕没点保存），也会立刻挂上晾衣绳。非官方项目，只公开源码，供自行编译使用。

## 跟原版不一样的地方

- **CleanShot X 截图即上绳**。CleanShot X 每次截图都会把「图片 + 媒体库文件 URL」复制到剪贴板，本版认出这个特征，CleanShot 截图无论保存与否都立刻挂上绳。与「挂上复制的图片」互不相干——普通复制的图片不受影响。开关在菜单栏：「CleanShot 截图」→「接管 CleanShot 截图」。
- **委托 CleanShot X 原生功能**。卡片右键菜单里多了「CleanShot ▸」：在 CleanShot 中编辑、在 CleanShot 中钉住、发送到 CleanShot 浮窗；悬停按钮里的 📌 和 ✎ 走同一个通道。
- **悬停按钮组**，样式照 CleanShot X 自己的浮层：鼠标停在卡片上，出现 ✕（扔掉）、📌（CleanShot 钉住）、✎（CleanShot 编辑）、居中的「复制 / 保存」胶囊（保存仅对收件箱文件出现，存到桌面）。录像只显示 ✕、复制、保存。
- **复制即下线**。任何复制动作（点一下卡片、点「复制」、用菜单）之后约 0.6 秒，卡片自动下线；收件箱文件随之进废纸篓（CleanShot X 媒体库里还有底档），其它来源只下线、不删文件。单击会先等一个系统双击间隔，所以双击打开预览时不会误触复制。
- **往下滚扔卡**。鼠标停在卡片上、往下滚约两格（累计约 36pt），卡片坠落下线，约等于点 ✕；没拉够就没事，惯性滚动不接力。

## 使用前提

- 已安装 CleanShot X；在其 after capture（截图后）动作里保持勾选 **Copy file to clipboard**——截图「不保存」也能上绳，靠的就是这个剪贴板事件
- 首次从卡片调 CleanShot 功能时，macOS 可能弹一次 URL scheme 授权，点允许

## 操作方式

| 操作 | 效果 |
|:--|:--|
| 点一下 | 复制图片；约 0.6 秒后卡片自动下线 |
| 双击 | 打开预览——不会先复制，也不下线 |
| 按住不放 | 在系统的「标记」里编辑（录像则进剪辑） |
| 用力按 | 快速查看 |
| 悬停卡片 | 出现 ✕ / 📌 / ✎ / 复制 / 保存 |
| 悬停时往下滚 | 卡片坠落下线 |
| 拖进 App | 送一份拷贝过去，卡片留在绳上 |
| 拖进文件夹 | 存进文件夹，卡片下线 |
| 拖到废纸篓，或点 ✕ | 扔掉 |
| 右键卡片 | 复制、打开、快速查看、标记、在访达中显示、CleanShot ▸、存储到桌面、丢弃 / 取下 |
| 指针停在菜单栏 | 放下晾衣绳 |
| ⌃⌥T | 显示或隐藏晾衣绳，可在菜单栏「快捷键」里改 |

其余（登录时打开、声音、大小、监视文件夹等）都在菜单栏里。

## 怎么运作

第一次打开「接管截图」时，macOS 的截图设置会被临时接管：关掉右下角浮动缩略图、把新截图存进 App 自己的收件箱文件夹、截图一按就上绳。你原来的设置会被记下，退出 App 或关掉这个选项时自动还回去。

CleanShot X 的截图走剪贴板通道：认出 CleanShot 的特征后直接上绳，不碰你的原文件；下线时处理的也只是收件箱里的副本。不联网、无账号、无分析，所有图片都留在你的 Mac 上。

## 从源码编译

```sh
git clone https://github.com/youtzz/tendedero.git
cd tendedero
scripts/build-app.sh
open build/Tendedero.app
```

需要 Swift 工具链（Xcode 可有可无）。本机构建用 ad-hoc 签名，所以每次重新编译后 macOS 可能再问一次「桌面文件夹」访问权限，点允许即可。要装进「应用程序」文件夹：

```sh
ditto build/Tendedero.app /Applications/Tendedero.app
```

## 授权与致谢

改自 [Alejandro Buján](https://alejandrobujan.com) 的 [Tendedero](https://github.com/alejandrobujan/tendedero) 1.5.0；原始代码按 MIT 授权，版权声明保留在 [LICENSE](LICENSE)。Tendedero 的名称与图标不在 MIT 授权范围内——本 fork 为非官方个人版本，不代表上游，也不发布二进制，只公开源码供自行编译。

`docs/` 下的图片和多语言说明来自上游原版，保留供参考，内容描述的是原版。
