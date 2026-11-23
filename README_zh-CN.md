# PsyReaWwise WebView

[English](README.md) · **简体中文**

PsyReaWwise WebView 0.2.0 Beta 2 是基于 ReaWebAPI 的可停靠工作台。可以取回 Wwise 原始音频，也可以把同一份渲染 WAV 传给 Wwise 并同步到 REAPER 工程的 `Samples`。[PsyReaWwise 0.1.0 发布页](https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.1.0)

## 安装到 REAPER

1. 同步 PRS ReaPack 订阅，安装 **PsyReaWwise WebView**。面板和 PRS 的 ReaWebAPI 运行时随包提供。离线安装时，解压完整 Windows x64 ZIP，在 REAPER 的 Action List 加载 `PsyReaWwise_WebView.lua`。[发布页与离线包](https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.2.0-beta2)
2. 运行 **PsyReaWwise WebView**。已加载兼容的 ReaWebAPI 时直接复用。首次安装时，动作会校验并准备随包运行时，然后提示完整重启一次 REAPER。面板打开后再次运行动作会聚焦窗口。
3. 安装 ReaWwise 1.0.4 或更新版以提供 WAAPI。在 Wwise 的 User Preferences 启用 WAAPI 并打开工程。面板默认使用本机 `127.0.0.1` 的 WAMP 端口 `8080`。

当前版本面向 Windows x64 和 REAPER 7.86 的区间 API。随包提供的 ReaWebAPI 0.3.9.30-prs.3 与 PRS 0.9.4 Beta 8 使用同一版本，采用 LGPL-3.0-or-later，包内包含匹配源码和许可证声明。[ReaWebAPI 文档](https://github.com/Psysia/ReaWebAPI)

面板启动时读取 PsyReaSFX 中保存的界面语言。启动提示，以及没有保存 PRS 语言时的面板，使用 Windows 显示语言。中文显示语言对应简体中文界面。

双语面板已在无界面 Chromium 中通过模拟桥接测试。Lua 消息处理和传输流程已通过 WwiseConsole 验证。已用独立 REAPER 7.86 渲染三个完全重叠的区间，验证逐轨输出、预设格式及峰值标准化。停靠仍待 REAPER 实机测试。

## 批量替换选中的 Wwise WAV

1. 在 REAPER 选中区间，在 Wwise Media Pool 选中要替换的 WAV，或者选中对应的音源或 Sound。点 **预览传输**。左侧显示 REAPER 区间，右侧显示所选的 Wwise Originals WAV。
2. 同名且两边各只有一个候选时会自动连线，匹配时忽略大小写和 `.wav` 扩展名。手动配对时先点区间，再点 WAV。再次点已连接的一对可断开。可以通过 WAV 的路径区分不同目录下的同名文件。
3. **同步到 Samples** 默认勾选，目标是当前 `.rpp` 同级的 `Samples` 文件夹，也可以选择已有导出目录。勾选时，已连线的 WAV 节点会标明是新增还是替换 Samples 副本。
4. REAPER 节点会显示各区间的渲染轨。使用区间渲染矩阵时，为每个配对区间勾选一个输出，可以是轨道或主轨。点 **渲染并替换** 处理已连线的配对。替换保留 Wwise 原文件名和音源 GUID。核验通过后，REAPER 区间名会跟随 Wwise 文件名，去掉扩展名。区间改名可在 REAPER 里一次撤销。

## 渲染设置

展开 **渲染设置**，可选 REAPER Render 面板中以 **所有设置** 保存的预设。面板显示源、范围、输出、采样率、声道、WAV 位深和后处理。选中区间与矩阵决定渲染内容。配对的 Wwise 原文件与 Samples 选项决定输出目录和文件名。

选择有且仅有一个 WAV 输出的预设。预设中的第二种输出格式会保存在暂存目录。使用 PRW 默认设置时，已配对区间沿用目标 WAV 的采样率及声道数。REAPER 加载 SWS 时，PRW 也会采纳预设中的渲染速度、重采样模式和内部工程采样率选项。批量渲染结束后，PRW 恢复原渲染设置和区间选择。

## 按 REAPER 渲染设置传输

REAPER 没有选中区间时，预览读取当前渲染范围和文件名。在 Wwise 选择参照音源、Sound 或容器，再选择 **Wwise 同级 / 容器内** 或 **Wwise 上一级**。例如，位于 `Originals/SFX/UI/Buttons/` 的参照音源会把同级文件放进 `Buttons`，上一级放进 `UI`。如果参照涉及多个 Originals 目录，请选中一个具体音源。

核对预览后点 **渲染并传输**。渲染的 24 位 WAV 会传给 Wwise，勾选同步时也会写入 REAPER 工程的 Samples 文件夹。

## 取回和更新已有音源

- 在 **导入到 REAPER** 读取 Wwise 选中项，勾选要取回的音源。工作台将副本放到 REAPER 的媒体目录，在编辑光标开始安排素材，可同时创建区间。手头已有素材时，可以用 **绑定到 REAPER 选中素材** 关联一个 Wwise 音源。区间模式在 **更新现有音源** 中切换。
- 在 **更新现有音源** 选定绑定的素材或区间，先预览再回写。素材逐件渲染，配置了矩阵的区间使用对应输出。**渲染设置**和**同步到 Samples** 在此页同样有效。同一 Originals 文件有多个引用时，预览会显示引用数和对象路径。
- 传输的暂存与备份位于 REAPER 媒体目录下的 `PsyReaWwise/Transfers`。发生部分失败时，面板分别列出已经核验的 Wwise 文件数和同步到 `Samples` 的文件数。
