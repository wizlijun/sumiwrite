# 0007 字体按需下载,不随宿主或插件打包

类型:补记
状态:已采纳;随宿主 6.1108.5 / 插件 0.1.4 首次公开,现行于基线 v6.1117.1。
记录日期:2026-11-18;用户于 2026-11-08 确认六项字体与“轻量宿主”(主规范 §2.2 及“轻量字体交付调整”)。

## 背景

用户最终确认六组写作字体,其中中文字体单个就有 7–31 MB。早期方案把字体内置进宿主,宿主 DMG 从约 13.5 MB 涨到 70.2 MB;用户在发布前指出这一点,并明确选择轻量宿主(主规范“轻量字体交付调整”)。

## 决定

- **六组选项、七个字体文件**,顺序固定(资源清单 `manifest.json` 的 `cascades`):
  1. Sumi Plex:IBM Plex Mono Light + IBM Plex Sans SC Light(两个文件)
  2. Sumi WenKai:LXGW WenKai Mono Lite Regular
  3. Sumi Zhaohua:朝华打字机
  4. Sumi Youcha:油茶馓子体
  5. Sumi Fangsong:朱雀仿宋 v0.212(来源为 ZIP,解出单个成员)
  6. Sumi CRT:GNU Unifont 18.0.01
- **点击才下载**:字体列表、打开设置、打开纸页及默认选择都不得隐式联网;只有用户点击字体项才启动后台下载。下载由插件后台负责,关闭设置、切换纸页或隐藏窗口不打断;同项请求去重,多次选择只有最后一次有权切换。
- **校验大小与 SHA-256**:只用清单中冻结的 HTTPS 地址;按清单校验文件大小、SHA-256 与实际字体身份(PostScript 名);ZIP 同时校验归档与目标字体。部分下载或损坏文件不成为可用字体,失败保留原字体并可重试。
- **不装入系统字体目录**:缓存位于应用私有数据目录,独立于 vault;macOS 以 CoreText 进程级作用域注册(`kCTFontManagerScopeProcess`),Linux 以 fontconfig 应用字体(`FcConfigAppFontAddFile`)加载。
- 字体目录与许可/来源文件随插件交付;宿主只保留小型字体身份契约与注册桥(见 [0006](0006-plugin-backend-vs-host-session.md))。
- 未下载时用系统等宽字体与系统中文回退,并明确显示所选字体尚未下载,不冒充所选字形。已不再提供的旧字体设置值统一迁移为第一组,保留其他外观设置。

## 放弃的方案

旧文档记录的:

- **字体内置进宿主**:§2.2 的原方案,已随公开宿主 6.1108.2 交付过(DMG 70,215,286 字节);被本方案覆盖(主规范“轻量字体交付调整”;迁移发布报告)。
- **字体打进插件包**:旧文档未单独记录比较过程;规范直接要求“宿主和插件均不内置上述七个大字体文件”(主规范 §2.2)。
- **CRT 组用 Terminus**:因不含常用中文、需要系统回退而排除,最终只分发 GNU Unifont(主规范 §2.2 与“轻量字体交付调整”)。

## 后果

得到的:

- 宿主与插件包都不带大字库;发布验收要同时报告宿主、插件与下载缓存体积,并断言无大字库打包。
- 字体与宿主发版解耦;换字体来源只改清单。

付出的:

- **首次使用依赖网络**:新用户默认第一组但不自动下载,第一眼看到的是系统回退字体。
- **依赖第三方托管的长期可用性**:清单里的地址指向 GitHub raw、GitHub Releases 与 unifoundry.com;任一上游撤下或改名,该组字体就无法新装,只能改清单发新插件。
- **不跨进程续传**:退出时未完成的下载,下次由用户重新点击。
- 许可不统一:朝华、油茶保留原作者许可快照,不能标成 OFL;每次换版本要重新核对许可与来源。
- 罕见字由系统回退,回退不保证全部可见;不能用有限样本推断覆盖范围。
- iOS 必须实现同一套目录、校验与回退规则(设计 §10.1),但注册方式与缓存位置是平台各自的实现,目前 `[未定]`。

## 来源

- 主规范 §2.2 及“轻量字体交付调整”“轻量宿主与插件后台正式发布”两节:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- 插件资源与后台迁移规范 §凭据与字体:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-08-plugin-payload-extraction.md
- 体积数据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-plugin-payload-extraction.md
- 字体清单(组合、大小、SHA-256、来源地址、许可):https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/resources/sumi/manifest.json
- 下载与校验:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/fonts.rs
- 注册:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/native/editor.m 、https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux.rs
- 设计 §10.1:note.md 源仓库 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`(note.md 仓库 `docs/sumiwrite-extraction` 分支,提交 `0c11629f`;该分支尚未推送到任何远端,暂不公开,见 [04-known-gaps §2.2](../handoff/04-known-gaps.md))
