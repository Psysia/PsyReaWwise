# PsyReaWwise WebView

[English](README.md) · **简体中文**

PsyReaWwise WebView 0.2.0 Beta 1 是基于 ReaWebAPI 的可停靠工作台。可以取回 Wwise 原始音频，也可以把同一份渲染 WAV 传给 Wwise 并同步到 REAPER 工程的 `Samples`。[PsyReaWwise 0.1.0 发布页](https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.1.0)

## 安装到 REAPER

1. 从 PRS ReaPack 订阅安装 **PsyReaSFX WebView Runtime**，也可使用对应的 ReaWebAPI 扩展。安装原生扩展后重启 REAPER。[ReaWebAPI 文档](https://github.com/Psysia/ReaWebAPI)
2. 将 `PsyReaWwise_WebView.lua`、`PsyReaWwise_WebView_Runtime.lua`、`lib` 和 `web` 保持在同一目录。在 REAPER 的 Action List 选择 **New action → Load ReaScript**，加载并运行 `PsyReaWwise_WebView.lua`。重复运行动作会聚焦已打开的窗口。
3. 在 Wwise 的 User Preferences 启用 WAAPI 并打开工程。面板默认使用本机 `127.0.0.1` 的 WAMP 端口 `8080`。

当前版本面向 Windows x64，依赖 REAPER 7 的区间 API、ReaWebAPI 的 Lua 消息接口和 ReaWwise 1.0.4 或更新版本。适用于 PRS WebView Runtime 0.3.9.30 或兼容的 ReaWebAPI 版本。

面板启动时读取 PsyReaSFX 中保存的界面语言。启动提示，以及没有保存 PRS 语言时的面板，使用 Windows 显示语言。中文显示语言对应简体中文界面。

双语面板已在无界面 Chromium 中通过模拟桥接测试。Lua 消息处理和传输流程已通过 WwiseConsole 与模拟 REAPER 接口验证。停靠和原生渲染仍待 REAPER 实机测试。

## 批量替换选中的 Wwise WAV

1. 在 REAPER 选中区间，在 Wwise Media Pool 选中要替换的 WAV，或者选中对应的音源或 Sound。点 **预览传输**。左侧显示 REAPER 区间，右侧显示所选的 Wwise Originals WAV。
2. 同名且两边各只有一个候选时会自动连线，匹配时忽略大小写和 `.wav` 扩展名。手动配对时先点区间，再点 WAV。再次点已连接的一对可断开。可以通过 WAV 的路径区分不同目录下的同名文件。
3. **同步到 Samples** 默认勾选，目标是当前 `.rpp` 同级的 `Samples` 文件夹，也可以选择已有导出目录。勾选时，已连线的 WAV 节点会标明是新增还是替换 Samples 副本。
4. 点 **渲染并替换** 处理已连线的配对。每个区间按目标 WAV 的采样率和声道数渲染主混音。替换保留 Wwise 原文件名和音源 GUID。核验通过后，REAPER 区间名会跟随 Wwise 文件名，去掉扩展名。区间改名可在 REAPER 里一次撤销。

## 按 REAPER 渲染设置传输

REAPER 没有选中区间时，预览读取当前渲染范围和文件名。在 Wwise 选择参照音源、Sound 或容器，再选择 **Wwise 同级 / 容器内** 或 **Wwise 上一级**。例如，位于 `Originals/SFX/UI/Buttons/` 的参照音源会把同级文件放进 `Buttons`，上一级放进 `UI`。如果参照涉及多个 Originals 目录，请选中一个具体音源。

核对预览后点 **渲染并传输**。渲染的 24 位 WAV 会传给 Wwise，勾选同步时也会写入 REAPER 工程的 Samples 文件夹。

## 取回和更新已有音源

- 在 **导入到 REAPER** 读取 Wwise 选中项，勾选要取回的音源。工作台将副本放到 REAPER 的媒体目录，在编辑光标开始安排素材，可同时创建区间。手头已有素材时，可以用 **绑定到 REAPER 选中素材** 关联一个 Wwise 音源。区间模式在 **更新现有音源** 中切换。
- 在 **更新现有音源** 选定绑定的素材或区间，先预览再回写。素材逐件渲染，区间以区间范围内的主混音渲染。回写保留原 WAV 的采样率及单声道或立体声格式。**同步到 Samples** 在此页同样有效。同一 Originals 文件有多个引用时，预览会显示引用数和对象路径。
- 传输的暂存与备份位于 REAPER 媒体目录下的 `PsyReaWwise/Transfers`。发生部分失败时，面板分别列出已经核验的 Wwise 文件数和同步到 `Samples` 的文件数。
