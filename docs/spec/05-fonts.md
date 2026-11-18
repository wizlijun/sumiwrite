# 05 字体

本文描述玄霜写作(Sumi Write)的正文字体:有哪些选项、按需下载、完整性校验、缓存、回退与离线行为、旧设置迁移,以及许可与来源。

- **唯一清单**:字体清单以插件资源 `plugins-src/write/resources/sumi/manifest.json`(schema 2)为准。别名与字面的对应关系由共享协议 `sumi-protocol/src/fonts.rs` 固定。插件后台启动时会核对两者一致。
- **平台细节**:进程内注册字体的平台做法(macOS CoreText、Linux Fontconfig)见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。
- **设计取舍**:为什么按需下载,见 [../adr/0007-fonts-on-demand.md](../adr/0007-fonts-on-demand.md)。

### 六组选项

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/manifest.json https://github.com/wizlijun/note.md/blob/v6.1117.1/sumi-protocol/src/fonts.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/contract.ts

外观面板按下表顺序列出六个可点击的选项。每项都显示大小和下载状态。

| 顺序 | 别名(偏好值) | 面板显示名 | 字面(PostScript 名) | 说明 |
|---|---|---|---|---|
| 1 | `Sumi Plex` | IBM Plex Mono Light + IBM Plex Sans SC Light | 英文 `IBMPlexMono-Light`,中文 `IBMPlexSansSC-Light` | 唯一的中英分字体组合,必须使用实际的 Light 字面 |
| 2 | `Sumi WenKai` | LXGW WenKai Mono Lite | `LXGWWenKaiMonoLite-Regular` | 中英文同一字族。Lite 指精简字符集,不是 Light 字重 |
| 3 | `Sumi Zhaohua` | 朝华打字机 | `ZhaohuaTypeWriter-Light` | 中英文同一字族 |
| 4 | `Sumi Youcha` | 油茶馓子体 | `YouchaSanz-Light` | 中英文同一字族 |
| 5 | `Sumi Fangsong` | Zhuque Fangsong · 朱雀仿宋 | `ZhuqueFangsong-Regular` | 中英文都用自身字形,不混配其他英文字体 |
| 6 | `Sumi CRT` | 复古绿磷 CRT · GNU Unifont | `Unifont` | GNU Unifont 一套字体承担中英文 |

- 第一组 `Sumi Plex` 是默认字体。
- 字体与主题分开选择。换字体不改主题、字号或行距。CRT 主题的配色见 [04-editing-experience.md](04-editing-experience.md)。
- 第 6 组只借用 cool-retro-term 的绿色配色作参考。不声称 GNU Unifont 是该项目的内置字体。
- 宿主和后台只接受上表六个别名,其他值一律拒绝。

### 七个字体文件

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/manifest.json https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/TerryWang-Typewriter-PROVENANCE.json https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/CRT-PROVENANCE.json

六组选项一共用到七个字体文件。每个文件的下载地址和 SHA-256 冻结在 manifest 中,这里不再重复。

| 文件 | 字面 | 版本 | 大小(字节) | 所属选项 |
|---|---|---|---:|---|
| `IBMPlexMono-Light.ttf` | `IBMPlexMono-Light` | [未定]。manifest 只固定了 google/fonts 提交 `03c54f8f` | 135,216 | 1 |
| `IBMPlexSansSC-Light.otf` | `IBMPlexSansSC-Light` | [未定]。manifest 只固定了 IBM/plex 提交 `222657a0` | 7,084,864 | 1 |
| `LXGWWenKaiMonoLite-Regular.ttf` | `LXGWWenKaiMonoLite-Regular` | v1.530 | 13,977,916 | 2 |
| `ZhaohuaTypeWriter.ttf` | `ZhaohuaTypeWriter-Light` | Version 1.001 | 27,492,440 | 3 |
| `YouchaSanz.ttf` | `YouchaSanz-Light` | Version 1.001 | 31,021,128 | 4 |
| `ZhuqueFangsong-Regular.ttf` | `ZhuqueFangsong-Regular` | v0.212 | 8,824,084(以 5,743,932 字节的 ZIP 下载) | 5 |
| `Unifont-18.0.01.otf` | `Unifont` | 18.0.01 | 5,320,148 | 6 |

- 七个文件合计 93,855,796 字节。外观面板以 MB 显示每一项的大小。
- 朝华和油茶的版本号取自字体内的 name 记录。其余版本取自下载地址或来源说明。
- 文件内容与上游一致,不修改、不子集化。

### 按需下载与状态显示

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/fonts.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/main.ts https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

**什么时候下载**

- 宿主和插件包都不内置这七个字体文件。插件只带 manifest,以及许可与来源说明等小文件。
- 只有用户点击某个字体项时,后台才开始下载。列出字体、打开设置、打开纸页、查询本地文件和默认选择,都不会触发下载。
- 下载和校验由玄霜写作的插件后台负责。宿主负责进程内注册字体,并把它安全地应用到原生编辑器。

**下载期间**

- 关闭设置、切换纸页或隐藏插件窗口,下载都继续。
- 正文可以照常编辑,仍用原来的字体显示。

**状态显示**

外观面板对每一项显示下列状态之一:

- 未下载,点击下载
- 准备下载…
- 下载中 N%(若这是正在等待生效的选择,则追加“完成后使用”)
- 正在应用…
- 已下载,点击使用
- 使用中
- 下载失败,点击重试

面板约每 750 ms 刷新一次状态 `(工程细则)`。

**多次选择与并发**

- 对同一项的并发请求会去重,共用一次下载。发起请求的一方取消后,下载仍会完成并进入缓存。
- 连续选了几个字体时,只有最后一次选择有权切换字体。先前的下载照样完成并缓存。
- 切换只更新字体偏好,同期对字号、主题等的修改都保留,不改正文、选区、行时间或 revision。
- 组字期间暂不切换原生样式,等组字结束后再切换。
- 下载或应用失败时,保留原来的字体,并提示“字体下载或应用失败，可在外观设置中重试”。

### 完整性校验与缓存位置

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/fonts.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/fonts.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs

**校验**

- 只从 manifest 冻结的 HTTPS 地址下载。重定向后的地址也必须是 HTTPS。
- 单个文件的传输上限是 64 MiB `(工程细则)`。
- 每个文件都严格校验大小和 SHA-256。
- 朱雀仿宋以 ZIP 下载,先校验归档的大小和 SHA-256。归档里必须恰好只有一个目标文件,解出后再校验该文件的大小和 SHA-256。成员名、数量不符或路径越界一律拒绝。
- 注册时核对字体的实际字面(PostScript 名)与别名约定一致。

**缓存**

- 缓存位于应用私有数据目录下的 `sumi/fonts/v1/`,与 Vault 无关,也不安装到系统字体目录。
- 每个文件按 `<SHA-256>/<文件名>` 存放。
- 下载先写入临时的 `.partial-*` 文件,校验通过后再改名就位。部分下载的文件、损坏的文件和符号链接都不算可用。
- 判定“已下载”之前会重新校验文件。文件元数据没有变化时,复用上次的校验结果。
- 宿主只接受落在缓存目录内的路径,未知别名一律拒绝。

**中断**

- 退出应用时,未完成的下载直接中止,下次由用户再点一次重试。
- 不支持跨进程续传。

### 回退与离线

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/main.ts

- 所选字体还没有可用缓存时,正文用系统字体显示,外观面板明确提示所选专用字体尚未下载。这时不会自动联网,不阻塞纸页,也不拿系统字形冒充所选字体。
- 这个运行时回退不是第七个选项,用户在面板里选不到它。
- 已校验的缓存可以离线使用。
- 中文罕见字缺字时,由系统字体补字。
- 无法加载字体的设备必须明确回退。今后若有子集字库,不能宣称它覆盖了完整的桌面字库。[未定]

### 旧设置迁移到第一组

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

- 读取偏好时,如果字体字段是已不再提供的旧字体设置值,或任何不在六组之内的值,只把字体字段改为第一组 `Sumi Plex`。
- 其他外观偏好(主题、字号、行距、列宽、光标动态等)和正文都保持不变。
- 字体字段已经是现有五组之一的旧设置原样保留。第 6 组 CRT 是独立选项,旧设置不会迁移到它。
- 新用户默认第一组,但不会自动下载。没有点击下载之前,正文按“回退与离线”显示。
- 被删除的旧字体选项,其许可与来源文件不恢复。旧值的具体拼写只记录在 [MAPPING.md](MAPPING.md)。

### 许可与来源

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/manifest.json https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/TerryWang-Typewriter-PROVENANCE.json https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/CRT-PROVENANCE.json

| 文件 | 许可 | 下载来源 | 许可文本 |
|---|---|---|---|
| `IBMPlexMono-Light.ttf` | OFL-1.1 | google/fonts 仓库,固定提交 | `IBMPlexMono-OFL.txt` |
| `IBMPlexSansSC-Light.otf` | OFL-1.1 | IBM/plex 仓库,固定提交 | `IBMPlexSansSC-LICENSE.txt` |
| `LXGWWenKaiMonoLite-Regular.ttf` | OFL-1.1 | lxgw/LxgwWenKai-Lite 发布 v1.530 | `LXGWWenKaiMonoLite-OFL.txt` |
| `ZhaohuaTypeWriter.ttf` | 作者许可(`LicenseRef-TerryWang-Typewriter`) | BH1PHL/ttf-terrywang-typewriter-fonts 镜像,固定提交 | `TerryWang-Typewriter-LICENSE.txt` |
| `YouchaSanz.ttf` | 作者许可(`LicenseRef-TerryWang-Typewriter`) | 同上 | `TerryWang-Typewriter-LICENSE.txt` |
| `ZhuqueFangsong-Regular.ttf` | OFL-1.1 | TrionesType/zhuque 发布 v0.212(ZIP) | `ZhuqueFangsong-LICENSE.txt` |
| `Unifont-18.0.01.otf` | OFL-1.1 | unifoundry.com 官方构建 | `Unifont-OFL.txt` |

**OFL-1.1 的五个文件**

Plex 的两个文件、文楷、朱雀仿宋和 Unifont 都是 OFL-1.1。

**作者许可的两个文件**

- 朝华打字机和油茶馓子体的作者是王廷瑞(TerryWang)。两者使用作者许可,不能标成 OFL。
- 作者官方的授权页把这两款字体列在“免商可修改”一类:允许免费商用、修改、嵌入和出版。
- 许可文本另有约束:不得把字体文件单独或打包出售牟利;字体包含不符合现代规范的写法,不宜用于用字要求严谨的场合或教育用途。
- 下载来源是一个非官方的打包镜像,保留了原作者署名和许可副本。

**来源说明文件**

- 插件资源里有三个来源说明文件。`TerryWang-Official-License.json` 是作者官方授权的快照。`TerryWang-Typewriter-PROVENANCE.json` 记录这两款字体的作者、官方出处、镜像提交和 name 记录。`CRT-PROVENANCE.json` 记录第 6 组的选型与配色来源。
- 七个文件在 manifest 中都冻结了版本来源、大小和 SHA-256。开发阶段准备与校验资源的脚本是源仓库的 `scripts/prepare-sumi-font.py`。
