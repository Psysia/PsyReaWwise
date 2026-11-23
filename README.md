# PsyReaWwise

**English** · [简体中文](README_zh-CN.md)

PsyReaWwise is a REAPER workbench for editing Wwise audio. Pull original audio into REAPER, then send the same rendered WAV to Wwise and to the REAPER project's `Samples` folder.

## Load in REAPER

1. Keep `PsyReaWwise.lua` and `lib` in the same folder. In the REAPER Action List, choose **New action → Load ReaScript**, select `PsyReaWwise.lua`, and run the action.
2. Open a project in Wwise and enable WAAPI in Wwise User Preferences. The workbench uses the local WAMP endpoint `127.0.0.1:8080` by default.

This version targets Windows and requires the REAPER 7 region APIs, ReaImGui 0.10, and ReaWwise 1.0.4 or later. The development setup uses REAPER 7.86, ReaWwise 1.1.0, and Wwise 2025.1.12.

The development build passed workflow tests with WwiseConsole and mocked REAPER APIs. The native REAPER panel and rendering still need a host test.

### ReaPack distribution

PsyReaWwise is maintained in its own repository. ReaPack distribution uses the existing [Psysia ReaPack Repository](https://github.com/Psysia/PsyReaSFX/blob/main/index.xml) subscription. A published entry needs publicly downloadable copies of the main script and its matching `lib` modules, installed with their relative paths intact. Use the Action List steps above for the development build.

## Transfer to Wwise and Samples

1. Save the `.rpp`. The default `Samples` folder sits next to it and can be created on the first transfer. To use an existing output folder, choose **选择 Samples 目录**. REAPER stores the choice in the project.
2. Set the render bounds and file names in REAPER's Render dialog. In Wwise, select an audio source, Sound, or container to use as the destination reference.
3. In **传输到 Wwise** (Transfer to Wwise), choose **Wwise 同级 / 容器内** (same level or inside the container) or **Wwise 上一级** (one level up). At the same level, a Sound uses its own container and Originals folder. A selected container is used directly. One level up moves both the Wwise destination container and the Originals subfolder up one level.
4. Click **预览传输** (Preview transfer). A reference in `Originals/SFX/UI/Buttons/` targets `Buttons` at the same level and `UI` one level up. The preview lists new or updated Wwise sounds and added or replaced files in `Samples`. Select a specific source if the reference spans multiple Originals folders.
5. Click **渲染并传输** (Render and transfer). The workbench renders 24-bit WAV files using the current REAPER bounds and file names, then uses each WAV for both destinations. A matched Wwise source keeps its GUID. The result shows where to find backups of replaced Originals and `Samples` files.

Use **打开 ReaWwise 高级传输** (Open ReaWwise) for the official ReaWwise hierarchy presets. Samples synchronization is part of the workbench's **渲染并传输** (Render and transfer) and **渲染并覆盖** (Render and update) actions.

## Pull and update existing sources

- In **导入到 REAPER** (Import into REAPER), read the Wwise selection and choose the sources you want. The workbench copies the media into REAPER's media directory, places items from the edit cursor, and can create a region for each item. You can also bind an existing item or region to a source. Switch between item and region mode in **更新现有音源** (Update existing sources).
- For a bound item or region, preview and run the update. Items render individually. Regions render the master mix over their bounds. The update preserves the sample rate and mono or stereo channel count of the original WAV and synchronizes `Samples`. The preview lists shared Originals references.
- Staged renders and backups are in `PsyReaWwise/Transfers` under the REAPER media directory. If a transfer stops partway through, the workbench reports the number of verified Wwise files and the number of synchronized `Samples` files.
