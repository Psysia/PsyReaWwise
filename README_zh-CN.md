# PsyReaWwise

[English](README.md) · **简体中文**

REAPER 内的 Wwise 音频工作台。可以取回 Wwise 原始音频，也可以把同一份渲染 WAV 传给 Wwise 并同步到 REAPER 工程的 `Samples`。

## 加载到 REAPER

1. 保留 `PsyReaWwise.lua` 和旁边的 `lib` 目录。在 REAPER 的 Action List 选择 **New action → Load ReaScript**，加载 `PsyReaWwise.lua`，运行对应动作。
2. 打开 Wwise 工程，在 Wwise 的 User Preferences 启用 WAAPI。面板默认使用本机 `127.0.0.1` 的 WAMP 端口 `8080`。

当前版本面向 Windows，依赖 REAPER 7 的区间 API、ReaImGui 0.10 和 ReaWwise 1.0.4 或更新版本。用于开发的本机版本为 REAPER 7.86、ReaWwise 1.1.0 和 Wwise 2025.1.12。

开发版已通过 WwiseConsole 和模拟 REAPER 接口的流程测试。实际 REAPER 面板和原生渲染仍待实机验证。

### ReaPack 分发

PsyReaWwise 在独立仓库维护。ReaPack 分发沿用 [Psysia ReaPack Repository](https://github.com/Psysia/PsyReaSFX/blob/main/index.xml) 的订阅入口。发布时，索引需要为主脚本和 `lib` 模块配置同一版本的可公开下载文件，并保留模块相对于主脚本的路径。当前开发版可按上面的步骤从 Action List 加载。

## 传输到 Wwise 和 Samples

1. 保存 `.rpp`。`Samples` 默认位于 `.rpp` 同级，首次传输时可以创建。已有自己的导出目录时，点 **选择 Samples 目录**。这个设置随 REAPER 工程保存。
2. 在 REAPER 的 Render 设置中选定渲染范围和文件命名。在 Wwise 中选择用作参照的音源、Sound 或容器。
3. 在 **传输到 Wwise** 选择 **Wwise 同级 / 容器内** 或 **Wwise 上一级**。同级以选中 Sound 所在容器和音源所在 Originals 目录为目标。选中容器时以容器本身为目标。上一级会把对象容器和 Originals 子目录各向上移动一级。
4. 点 **预览传输** 核对目标和文件名。比如 `Originals/SFX/UI/Buttons/` 中的参照音源会把同级文件放进 `Buttons`，上一级放进 `UI`。预览会同时标明 Wwise 是否新建 Sound 或更新音源，以及 `Samples` 中是新增还是替换。多个 Originals 目录都可能匹配时，选中一个具体音源作为参照。
5. 点 **渲染并传输**。工作台按 REAPER 当前范围和命名渲染 24 位 WAV，使用同一份文件更新 Wwise 和 `Samples`。同名且能确认是已有 Wwise 音源时会保留其 GUID。原始文件及同名 `Samples` 文件的备份可从面板结果中的目录找到。

**打开 ReaWwise 高级传输** 会打开官方面板，供需要 ReaWwise 层级预设的工作使用。`Samples` 同步由本工作台的 **渲染并传输** 或 **渲染并覆盖** 执行。

## 取回和更新已有音源

- 在 **导入到 REAPER** 读取 Wwise 选中项，勾选要取回的音源。工作台将副本放到 REAPER 的媒体目录，在编辑光标开始安排素材，可同时创建区间。手头已有素材时，可以用 **绑定到 REAPER 选中素材** 关联一个 Wwise 音源。区间模式在 **更新现有音源** 中切换。
- 在 **更新现有音源** 选定绑定的素材或区间，先预览再回写。素材逐件渲染，区间以区间范围内的主混音渲染。回写保留原 WAV 的采样率及单声道或立体声格式，也同步 `Samples`。同一 Originals 文件有多个引用时，预览会显示引用数和对象路径。
- 传输的暂存与备份位于 REAPER 媒体目录下的 `PsyReaWwise/Transfers`。发生部分失败时，面板分别列出已经核验的 Wwise 文件数和同步到 `Samples` 的文件数。
