<p align="center">
  <a href="https://github.com/Psysia/PsyReaSFX">
    <img src="assets/brand/psyreasfx-hero.png" alt="Psysia REAPER Tools" width="100%">
  </a>
</p>

# PsyReaWwise WebView

**English** · [简体中文](README_zh-CN.md)

Edit Wwise audio in REAPER, then replace the selected Originals with renders from the matching regions. Review the routing, choose a REAPER render preset, and optionally sync the same WAVs to the REAPER project's `Samples` folder.

[0.2.0 Beta 2 release notes](https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.2.0-beta2) · [Windows x64 ZIP](https://github.com/Psysia/PsyReaSFX/releases/download/psyreawwise-v0.2.0-beta2/PsyReaWwise-WebView-0.2.0-beta2-win64.zip) · [PsyReaSFX (PRS)](https://github.com/Psysia/PsyReaSFX)

## Install

**Requirements** Windows x64, REAPER 7 with region selection APIs (tested on 7.86), and ReaWwise 1.0.4 or later for WAAPI. Enable WAAPI in Wwise User Preferences and open your project. PRW defaults to `127.0.0.1:8080`. [ReaWwise](https://github.com/audiokinetic/ReaWwise)

1. In REAPER, open **Extensions → ReaPack → Import repositories** and add the PRS subscription. If you already subscribe to PRS, start at step 2.

   ```text
   https://raw.githubusercontent.com/Psysia/PsyReaSFX/main/index.xml
   ```

2. Run **Synchronize packages** and install **PsyReaWwise WebView**. The WebView panel and ReaWebAPI runtime are included.
3. Run `PsyReaWwise_WebView.lua` from the Action List. A compatible loaded ReaWebAPI is reused. On a fresh setup, the action prepares the bundled runtime and prompts you to restart REAPER once.

For an offline install, extract the entire ZIP and load `PsyReaWwise_WebView.lua` through **Action List → New action → Load ReaScript**. The legacy 0.1.0 edition remains available as a separate package. [0.1.0 release](https://github.com/Psysia/PsyReaSFX/releases/tag/psyreawwise-v0.1.0)

## Replace Wwise WAVs

1. **Select the audio.** Select regions in REAPER and their target WAVs in Wwise Media Pool, or select the corresponding Wwise sources or Sounds. For region render matrix projects, assign one output to each region you plan to pair. The matrix can point to a track or the master.
2. **Preview the pairs.** Open **Transfer to Wwise → Preview transfer**. Unique matching names connect automatically, ignoring case and the `.wav` extension. Click a region and a WAV to connect them manually. The REAPER node shows its render track, and the Wwise node shows its Originals folder.
3. **Review render settings.** Open **Render settings** to use a preset saved as **All settings** in REAPER. Review the sample rate, channels, WAV depth, normalization, limiter, fades, and tail. The selected regions and matrix supply the source and bounds.
4. **Render and replace.** PRW keeps the target Wwise filename and source GUID. After verification, the REAPER region takes the WAV's basename. Regions renamed in one batch can be undone together in REAPER.

**Sync to Samples** is enabled by default. It writes the same WAV next to the current `.rpp` in `Samples`, or to an export folder you choose. The preview shows whether each Samples file will be added or replaced.

### Presets and output

Choose a preset with one WAV output for Wwise replacement. A secondary format is rendered to staging. PRW defaults use the target WAV's sample rate and channel count for paired regions. If SWS is loaded, PRW can also apply preset render speed, resampling mode, and the internal project-rate option. PRW restores the render settings and region selection after the batch.

## More workflows

| I want to | In PsyReaWwise |
| --- | --- |
| Bring Wwise audio into REAPER | In **Import into REAPER**, read the Wwise selection and import working copies. You can also create regions or bind an existing item or region to a Wwise source. |
| Update a bound item or region | In **Update existing sources**, select the bound items or regions, preview the targets, and publish. Assigned region matrix outputs are used when configured. |
| Send files using the current REAPER render range | With no regions selected, choose a Wwise source, Sound, or container as the destination reference. Preview **Same level / Inside container** or **One level up** and render to that destination. |

Staged renders and backups are saved in `PsyReaWwise/Transfers` under the REAPER media directory. The result reports how many Wwise files were verified and how many Samples copies were synchronized.

## Use with PsyReaSFX

Find, audition, and organize local sound effects in **PsyReaSFX (PRS)**. Its REAPER workspace includes waveform audition, UCS browsing, and similarity search. Once the sound is in your session, use PsyReaWwise to send the finished audio to Wwise. Both tools are available through the same PRS ReaPack subscription. [Explore PsyReaSFX and its REAPER tools](https://github.com/Psysia/PsyReaSFX)

## Runtime and verification

PsyReaWwise uses the PRS dark palette and the language selected in PRS. The Windows display language sets the default when PRS has no language preference.

The package ships ReaWebAPI 0.3.9.30-prs.3 under LGPL-3.0-or-later and includes the corresponding source and license notices. [Runtime lock](runtime/reawebapi/runtime-lock.json) · [ReaWebAPI](https://github.com/Psysia/ReaWebAPI)

The bilingual panel passed headless Chromium tests and the Wwise transfer workflow passed WwiseConsole tests. Isolated REAPER 7.86 tests verified distinct outputs for three overlapping regions, preset format, and peak normalization. Native docking acceptance is pending.
