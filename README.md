# PsyReaWwise WebView

**English** · [简体中文](README_zh-CN.md)

PsyReaWwise WebView 0.2.0 Beta 1 is a dockable ReaWebAPI workbench for editing Wwise audio. Pull originals into REAPER, then send the same rendered WAV to Wwise and the REAPER project's `Samples` folder. [PsyReaWwise 0.1.0 release](https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.1.0)

## Install in REAPER

1. Synchronize the PRS ReaPack subscription and install **PsyReaWwise WebView**. The package includes the panel and the PRS ReaWebAPI runtime. For an offline install, extract the full Windows x64 ZIP and load `PsyReaWwise_WebView.lua` from the REAPER Action List. [Release and offline ZIP](https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.2.0-beta1)
2. Run **PsyReaWwise WebView**. A compatible active ReaWebAPI is reused. On a fresh setup the action installs the checked bundled runtime, then prompts you to restart REAPER once. Running the action when the panel is open focuses it.
3. Install ReaWwise 1.0.4 or later for WAAPI. Enable WAAPI in Wwise User Preferences and open a project. The workbench defaults to the local WAMP endpoint `127.0.0.1:8080`.

This version targets Windows x64 and the REAPER 7.86 region APIs. The bundled ReaWebAPI 0.3.9.30-prs.3 is the same LGPL-3.0-or-later runtime used by PRS 0.9.4 Beta 8. The package includes the matching source archive and license notices. [ReaWebAPI documentation](https://github.com/Psysia/ReaWebAPI)

The panel loads the language selected in PsyReaSFX when that preference is available. It uses the Windows display language for setup prompts and when no PRS language is saved. Chinese display languages use the Simplified Chinese interface.

The bilingual panel passed headless Chromium tests with a mock bridge. The Lua message handlers and transfer workflow passed WwiseConsole tests with mocked REAPER APIs. Docking and native rendering still need an in-REAPER test.

## Replace WAVs from selected regions

1. Select the regions in REAPER and the corresponding WAVs in the Wwise Media Pool or their sources or Sounds. Click **Preview transfer**. The graph shows the REAPER regions on the left and the selected Wwise Originals WAVs on the right.
2. Unique names connect automatically, ignoring case and the `.wav` extension. To pair any region manually, click its node and then the Wwise WAV. Repeat with a connected pair to disconnect it. The WAV's path identifies its folder when names repeat.
3. **Sync to Samples** starts checked. The default folder is `Samples` next to the current `.rpp`. Choose an existing export folder if needed. With sync enabled, each connected WAV node shows whether its Samples copy will be added or replaced.
4. Click **Render and replace** to process the connected pairs. Each region renders its master mix at the original WAV's sample rate and channel count. The verified replacement keeps the Wwise filename and source GUID. The REAPER region adopts the WAV's name without the extension. Region renames are grouped in one REAPER undo step.

## Transfer using REAPER render settings

With no regions selected, the preview uses the current REAPER render bounds and filenames. Select a Wwise source, Sound, or container as the destination reference, then choose **Same level / Inside container** or **One level up**. For example, a source in `Originals/SFX/UI/Buttons/` targets `Buttons` at the same level and `UI` one level up. Select a specific source if the reference spans multiple Originals folders.

Review the destination and click **Render and transfer**. The 24-bit WAVs go to Wwise and, with sync enabled, the REAPER project's Samples folder.

## Pull and update existing sources

- In **Import into REAPER**, read the Wwise selection and choose the sources you want. The workbench copies the media into REAPER's media directory, places items from the edit cursor, and can create a region for each item. You can also bind an existing item or region to a source. Switch between item and region mode in **Update existing sources**.
- For a bound item or region, preview and run the update. Items render individually. Regions render the master mix over their bounds. The update preserves the original WAV's sample rate and mono or stereo channel count. **Sync to Samples** also applies here. The preview lists shared Originals references.
- Staged renders and backups are in `PsyReaWwise/Transfers` under the REAPER media directory. If a transfer stops partway through, the workbench reports the number of verified Wwise files and the number of synchronized `Samples` files.
