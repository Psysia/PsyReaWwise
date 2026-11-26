"use strict";

const app = document.getElementById("app");
const pending = new Map();
const state = {
  tab: "transfer",
  mode: "items",
  placement: "same",
  makeRegions: true,
  syncSamples: true,
  renderPreset: "",
  renderPresets: [],
  checked: new Set(),
  status: "",
};
const native = window.reaper;
let sequence = 0;
let drawConnections;

function request(method, params = {}) {
  const id = "wv-" + Date.now() + "-" + (++sequence);
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    Promise.resolve().then(() => native.host.send({ protocol: 1, id, method, params }))
      .catch(() => {
        pending.delete(id);
        reject(new Error(state.labels?.requestFailed || "Could not connect to REAPER."));
      });
  });
}

function receive(raw) {
  let message;
  try {
    message = typeof raw === "string" ? JSON.parse(raw) : raw;
  } catch {
    return;
  }
  if (message?.protocol !== 1) return;
  if (message.event === "project" && message.data && state.labels) {
    applyProject(message.data);
    render();
    return;
  }
  const match = pending.get(message.id);
  if (!match || typeof message.ok !== "boolean") return;
  pending.delete(message.id);
  if (message.ok) match.resolve(message.result);
  else match.reject(new Error(message.error || state.labels?.requestFailed));
}

function format(label, ...values) {
  let index = 0;
  return label.replace(/%[ds]/g, () => String(values[index++]));
}

function node(tag, className, ...children) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  element.append(...children.filter((child) => child !== undefined && child !== null && child !== false));
  return element;
}

function applyProject(next) {
  const old = state.project;
  if (old?.epoch !== next.epoch || old?.port !== next.port) {
    state.pull = state.update = state.transfer = undefined;
    state.checked = new Set();
  }
  state.project = next;
}

async function run(method, params, progress, apply, focus = document.activeElement?.dataset?.focus) {
  if (state.busy) return;
  state.busy = true;
  state.error = false;
  state.status = progress || "";
  render();
  try {
    const result = await request(method, { epoch: state.project.epoch, ...params });
    if (result?.project && typeof result.project === "object") applyProject(result.project);
    if (apply) apply(result);
    state.error = result?.error === true;
    state.status = result?.message || "";
    return true;
  } catch (error) {
    state.error = true;
    state.status = error.message || state.labels.requestFailed;
    return false;
  } finally {
    state.busy = false;
    render(focus);
  }
}

function button(key, label, action, enabled = true, primary = false) {
  const element = node("button", primary ? "button primary" : "button", label);
  element.type = "button";
  element.dataset.focus = key;
  element.disabled = state.busy || !enabled;
  element.addEventListener("click", action);
  return element;
}

function segments(name, choices, active, onChange) {
  const group = node("div", "segmented");
  for (const [value, title] of choices) {
    const control = button(name + "-" + value, title, () => {
      onChange(value);
      render();
    });
    control.className = "segment";
    control.setAttribute("aria-pressed", String(active === value));
    group.append(control);
  }
  return group;
}

function table(columns, rows) {
  const wrapper = node("div", "table-wrapper");
  wrapper.tabIndex = 0;
  const headings = columns.map(([name, css]) => {
    const cell = node("th", css, name);
    cell.scope = "col";
    return cell;
  });
  wrapper.append(node("table", "",
    node("thead", "", node("tr", "", ...headings)),
    node("tbody", "", ...rows),
  ));
  return wrapper;
}

function textCell(text, title, css) {
  const cell = node("td", css, text || "—");
  if (title) cell.title = title;
  return cell;
}

function samplesControls() {
  const l = state.labels;
  const check = node("input");
  check.type = "checkbox";
  check.checked = state.syncSamples;
  check.disabled = state.busy;
  check.dataset.focus = "sync-samples";
  check.addEventListener("change", () => {
    state.syncSamples = check.checked;
    state.update = undefined;
    if (state.transfer?.kind === "regions") {
      remapRegions(state.transfer);
      return;
    }
    state.transfer = undefined;
    render();
  });
  const switchTrack = node("span", "switch-track");
  switchTrack.setAttribute("aria-hidden", "true");
  const toggle = node("label", "toggle sync-toggle", check, switchTrack, l.syncSamples);
  if (!state.syncSamples) return node("div", "folder-control", toggle);

  const folder = node("span", "folder-name muted", state.project.samples || l.samplesHint);
  folder.title = folder.textContent;
  return node("div", "folder-control", toggle, folder,
    button("samples-choose", l.samplesChoose, () => run("samples.choose", {}, l.choosing)),
    state.project.customSamples
      ? button("samples-default", l.samplesDefault, () => run("samples.reset", {}, l.choosing))
      : undefined,
  );
}

function renderSetup(mode, graph, plan) {
  const l = state.labels;
  const preset = state.renderPresets.find((item) => item.name === state.renderPreset);
  const choose = node("select", "render-preset", new Option(l.defaultPreset, ""));
  choose.dataset.focus = "render-preset";
  choose.disabled = state.busy;
  for (const entry of state.renderPresets) {
    const option = new Option(entry.valid ? entry.name : entry.name + " · " + l.wavPresetOnly, entry.name);
    option.disabled = !entry.valid;
    choose.append(option);
  }
  choose.value = preset?.name || "";
  choose.addEventListener("change", () => {
    state.renderPreset = choose.value;
    state.update = undefined;
    if (graph) remapRegions(graph);
    else {
      state.transfer = undefined;
      render();
    }
  });
  const reload = button("refresh-render-presets", l.refreshPresets, async () => {
    const refreshed = await run("render.presets", {}, "", (result) => {
      state.renderPresets = result.renderPresets;
      state.presetError = undefined;
      if (!state.renderPresets.some((entry) => entry.name === state.renderPreset && entry.valid)) state.renderPreset = "";
      state.update = undefined;
      if (!graph) state.transfer = undefined;
    });
    if (refreshed && state.transfer === graph && graph) remapRegions(graph);
  });
  const section = node("details", "render-setup");
  section.open = state.renderExpanded === true;
  section.addEventListener("toggle", () => { if (section.isConnected) state.renderExpanded = section.open; });
  const field = (label, value) => node("div", "render-field", node("dt", "", label), node("dd", "", value));
  const scope = graph || mode === "regions";
  const source = graph ? (graph.regions.some((region) => region.matrix) ? l.regionMatrix : l.mainMix)
    : mode === "regions" && plan ? (plan.matrix ? l.regionMatrix : l.mainMix)
      : mode === "items" ? l.items : l.projectRender;
  const channelCount = preset?.channels;
  const defaultFormat = graph || mode ? l.retainOriginal : l.projectRender;
  const defaultProcessing = !preset && !graph && !mode ? l.projectRender : l.off;
  const channelText = channelCount === 1 ? l.mono : channelCount === 2 ? l.stereo : channelCount ? String(channelCount) : defaultFormat;
  const normalization = preset?.normalization
    ? preset.normalization + (typeof preset.target === "number" ? " · " + preset.target + (preset.normalization.startsWith("LUFS") ? " LUFS" : " dB") : "")
    : defaultProcessing;
  const fade = preset?.fadeIn || preset?.fadeOut
    ? [preset.fadeIn || 0, preset.fadeOut || 0].map((seconds) => Math.round(seconds * 1000) + " ms").join(" / ")
    : defaultProcessing;
  section.append(node("summary", "", node("strong", "", l.renderSetup), node("span", "muted", preset?.name || l.defaultPreset)),
    node("div", "render-body",
      node("div", "render-preset-line", node("label", "", l.renderPreset, choose), reload),
      state.presetError && node("p", "render-message", state.presetError),
      !state.renderPresets.length && node("p", "render-message muted", l.noPresets),
      node("dl", "render-fields",
        field(l.renderSource, source),
        field(l.renderBounds, scope ? (graph ? l.connectedRegions + " · " + new Set(graph.links.values()).size : l.selectedRegions)
          : mode === "items" ? l.items : l.projectRender),
        field(l.renderOutput, state.syncSamples ? "Wwise Originals + Samples" : "Wwise Originals"),
        field(l.renderFormat, "WAV · " + (preset?.bits || 24) + " bit"),
        field(l.renderSampleRate, preset ? preset.rate ? preset.rate + " Hz" : l.projectRate : defaultFormat),
        field(l.renderChannels, channelText),
        field(l.renderNormalize, normalization),
        field(l.renderLimiter, typeof preset?.limiter === "number" ? preset.limiter + " dB" : defaultProcessing),
        field(l.renderTail, preset?.tail ? preset.tail + " ms" : defaultProcessing),
        field(l.renderFade, fade),
      ),
    ),
  );
  return section;
}

function pullActions() {
  const l = state.labels;
  const pull = state.pull;
  const importable = state.project.waapi;
  const choose = (sources) => {
    state.checked = new Set(sources.filter((source) => source.wav).map((source) => source.id));
  };
  const toggle = node("input");
  toggle.type = "checkbox";
  toggle.checked = state.makeRegions;
  toggle.disabled = state.busy;
  toggle.dataset.focus = "create-regions";
  toggle.addEventListener("change", () => { state.makeRegions = toggle.checked; });

  const bar = node("div", "toolbar",
    button("read-selection", l.readSelection, () => {
      state.pull = undefined;
      state.checked.clear();
      run("pull.read", {}, l.reading, (result) => {
        state.pull = result;
        choose(result.sources);
      });
    }, importable),
    node("label", "toggle", toggle, l.regions),
    node("div", "actions", button("pull-import", format(l.importCount, state.checked.size), () => {
      run("pull.import", { ids: Array.from(state.checked), regions: state.makeRegions }, l.importing, () => {
        state.update = state.transfer = undefined;
      });
    }, importable && state.checked.size > 0, true)),
  );

  if (!pull || pull.sources.length === 0) {
    const hint = !importable ? l.needWaapi : pull ? l.emptySelection : l.pullHint;
    return [bar, node("p", "hint", hint)];
  }
  const bind = button("pull-bind", format(l.bindTo, state.mode === "items" ? l.item : l.region), () => {
    run("pull.bind", { ids: Array.from(state.checked), mode: state.mode }, l.binding, () => {
      state.update = undefined;
    });
  }, importable && state.checked.size === 1);
  bind.title = l.bindHint;
  const choices = node("div", "toolbar", node("span", "muted", pull.project),
    button("check-all", l.chooseAll, () => { choose(pull.sources); render(); }),
    button("check-none", l.clear, () => { state.checked.clear(); render(); }),
    bind,
  );
  const rows = pull.sources.map((source) => {
    const check = node("input");
    check.type = "checkbox";
    check.checked = state.checked.has(source.id);
    check.disabled = state.busy || !source.wav;
    check.dataset.focus = "source-" + source.id;
    check.setAttribute("aria-label", source.name);
    check.addEventListener("change", () => {
      if (check.checked) state.checked.add(source.id);
      else state.checked.delete(source.id);
      render();
    });
    return node("tr", "", node("td", "check-column", check),
      textCell(source.name, source.path), textCell(source.language, "", "short-column"),
      textCell(source.relative || l.noOriginal, source.wav));
  });
  return [bar, choices, table([["", "check-column"], [l.source], [l.language], [l.originals]], rows)];
}

function disposition(text, className, title) {
  return textCell(text, title, "operation " + className);
}

function previewTable(plan, kind) {
  const l = state.labels;
  const rows = plan.rows.map((row) => {
    const samples = plan.syncSamples && disposition(row.replace ? l.replace : l.add, row.replace ? "replace" : "add", row.sample);
    const references = row.references.join("\n");
    const action = row.existing ? l.updateSource : l.newSound;
    const detail = kind === "update"
      ? [textCell(row.format, "", "short-column"), textCell(String(row.references.length), references, "short-column")]
      : [disposition(action + (row.references.length > 1 ? l.shared : ""), row.existing ? "replace" : "add", references)];
    return node("tr", "",
      textCell(row.name), textCell(row.originals, row.originalsPath), ...detail, samples,
    );
  });
  const columns = kind === "update"
    ? [["REAPER"], [l.originals], [l.renderFormat], [l.referenceCount]]
    : [["WAV"], [l.originals], ["Wwise"]];
  if (plan.syncSamples) columns.push(["Samples"]);
  return table(columns, rows);
}

function updateActions() {
  const l = state.labels;
  const plan = state.update;
  const isReady = state.project.waapi && (!state.syncSamples || Boolean(state.project.samples));
  const modes = segments("update-mode", [["items", l.items], ["regions", l.selectedRegions]], state.mode, (value) => {
    state.mode = value;
    state.update = undefined;
  });
  const commands = node("div", "toolbar", modes,
    button("preview-update", l.previewUpdate, () => {
      state.update = undefined;
      run("update.preview", { mode: state.mode, syncSamples: state.syncSamples, renderPreset: state.renderPreset }, l.checking, (result) => {
        state.update = result;
      });
    }, isReady),
    plan && node("div", "actions", button("publish-update", format(l.updateCount, plan.rows.length), () => {
      state.update = undefined;
      run("update.publish", { preview: plan.id }, l.updating, () => { state.transfer = undefined; });
    }, isReady, true)),
  );
  const hint = !state.project.waapi ? l.needWaapi
    : plan ? l.updateNote : state.mode === "items" ? l.itemUpdateHint : l.regionUpdateHint;
  return [samplesControls(), renderSetup(state.mode, undefined, plan), commands, node("p", "hint", hint), plan && previewTable(plan, "update")];
}

function remapRegions(graph, focus) {
  graph.plan = undefined;
  run("transfer.map", {
    draft: graph.draft, links: Object.fromEntries(graph.links),
    syncSamples: state.syncSamples, renderPreset: state.renderPreset,
  }, "", (result) => {
    if (state.transfer === graph) graph.plan = result.plan;
  }, focus);
}

function editRoute(graph, target, region) {
  graph.activeRegion = undefined;
  graph.selectedTarget = region ? target : undefined;
  const focus = "wav-node-" + target;
  if (graph.links.get(target) === region) {
    render(focus);
    return;
  }
  if (region) graph.links.set(target, region);
  else graph.links.delete(target);
  remapRegions(graph, focus);
}

function regionGraph(graph) {
  const l = state.labels;
  const regions = node("div", "pair-column");
  const wavs = node("div", "pair-column");
  const grid = node("div", "pair-grid", regions, wavs);
  const viewport = node("div", "graph-wrapper", grid);
  const regionNodes = new Map();
  const wavNodes = new Map();
  const targetsByRegion = new Map();
  const previewRows = new Map((graph.plan?.rows || []).map((row) => [row.targetId, row]));
  const wires = new Map();
  let drag, animation, ignoreClick;

  for (const target of graph.targets) {
    const region = graph.links.get(target.id);
    if (!region) continue;
    if (!targetsByRegion.has(region)) targetsByRegion.set(region, []);
    targetsByRegion.get(region).push(target);
  }

  function updateSelection() {
    const selectedRegion = graph.links.get(graph.selectedTarget);
    for (const [id, { control }] of regionNodes) {
      control.setAttribute("aria-pressed", String(graph.activeRegion === id));
      control.classList.toggle("route-active", selectedRegion === id);
    }
    for (const [id, { control }] of wavNodes) {
      control.setAttribute("aria-pressed", String(graph.selectedTarget === id));
    }
    for (const [id, wire] of wires) {
      wire.classList.toggle("active", graph.selectedTarget === id || graph.links.get(id) === graph.activeRegion);
    }
    grid.classList.toggle("source-armed", Boolean(graph.activeRegion));
  }

  function selectCable(id) {
    graph.activeRegion = undefined;
    graph.selectedTarget = graph.links.has(id) ? id : undefined;
    updateSelection();
  }

  function socket(control) {
    const port = node("span", "pair-port");
    port.setAttribute("aria-hidden", "true");
    control.append(port);
    return port;
  }

  for (const region of graph.regions) {
    const linked = targetsByRegion.get(region.id) || [];
    const nextName = linked.length === 1 ? linked[0].name.replace(/\.wav$/i, "") : undefined;
    const naming = linked.length > 1 ? format(l.reuseName, linked.length)
      : nextName && nextName !== region.name ? format(l.renameTo, nextName) : "";
    const name = region.name || l.unnamedRegion;
    const control = button("region-node-" + region.id, "", (event) => {
      if (event.detail && ignoreClick === region.id) return;
      graph.activeRegion = graph.activeRegion === region.id ? undefined : region.id;
      graph.selectedTarget = undefined;
      updateSelection();
    }, region.renderable);
    control.className = "pair-node region-node";
    control.title = [name, region.renderLabel, region.renderError, naming].filter(Boolean).join("\n");
    control.dataset.linked = String(linked.length > 0);
    const track = region.renderError || region.renderLabel;
    control.append(node("span", "pair-title", name),
      node("span", "pair-detail", node("span", "region-number", "R" + region.number), track && " · " + track),
      naming && node("span", "pair-detail route-name", naming));
    if (region.renderError) control.classList.add("render-unavailable");
    regionNodes.set(region.id, { control, port: socket(control) });
    control.addEventListener("pointerdown", (event) => {
      if (control.disabled || event.button !== 0 || drag) return;
      ignoreClick = undefined;
      const { clientX: x, clientY: y, pointerId } = event;
      drag = { region: region.id, x, y, startX: x, startY: y, pointerId };
      control.setPointerCapture(pointerId);
    });
    regions.append(control);
  }

  for (const target of graph.targets) {
    const linked = graph.links.has(target.id);
    const row = previewRows.get(target.id);
    const control = button("wav-node-" + target.id, "", () => {
      if (graph.activeRegion) editRoute(graph, target.id, graph.activeRegion);
      else selectCable(target.id);
    });
    control.className = "pair-node wav-node";
    control.title = [target.originalsPath, ...(row?.references || []), row?.sample].filter(Boolean).join("\n");
    control.dataset.linked = String(linked);
    control.dataset.targetId = target.id;
    const directory = target.originals.replace(/[\\/][^\\/]+$/, "");
    const shared = target.references > 1 ? l.shared : "";
    control.append(node("span", "pair-title", target.name), node("span", "pair-detail", directory + shared));
    if (row?.sample) control.append(node("span", "pair-detail sample-operation",
      "Samples · " + (row.replace ? l.replace : l.add)));
    wavNodes.set(target.id, { control, port: socket(control) });
    const card = node("div", "wav-card", control);
    if (linked) {
      const disconnect = button("disconnect-" + target.id, "×", () => editRoute(graph, target.id));
      disconnect.className = "disconnect";
      disconnect.title = format(l.disconnect, target.name);
      disconnect.setAttribute("aria-label", disconnect.title);
      card.classList.add("has-disconnect");
      card.append(disconnect);
    }
    wavs.append(card);
  }

  const svgNamespace = "http://www.w3.org/2000/svg";
  const svg = (tag, css) => {
    const element = document.createElementNS(svgNamespace, tag);
    element.classList.add(css);
    return element;
  };
  const connections = svg("svg", "pair-connections");
  connections.setAttribute("aria-hidden", "true");
  for (const [target] of graph.links) {
    const wire = svg("g", "cable");
    const line = svg("path", "cable-line");
    const hit = svg("path", "cable-hit");
    hit.addEventListener("click", () => {
      if (state.busy) return;
      selectCable(target);
      wavNodes.get(target).control.focus({ preventScroll: true });
    });
    wire.append(line, hit);
    wires.set(target, wire);
    connections.append(wire);
  }
  const ghost = svg("path", "cable-preview");
  connections.append(ghost);
  grid.append(connections);

  function cablePath(from, to, bounds) {
    const x1 = from.x - bounds.left;
    const x2 = to.x - bounds.left;
    const y1 = from.y - bounds.top;
    const y2 = to.y - bounds.top;
    const bend = Math.max(22, (x2 - x1) * .5);
    return ["M", x1, y1, "C", x1 + bend, y1, x2 - bend, y2, x2, y2].join(" ");
  }

  function center({ port }) {
    const { left, top, width, height } = port.getBoundingClientRect();
    return { x: left + width / 2, y: top + height / 2 };
  }

  drawConnections = () => {
    const bounds = connections.getBoundingClientRect();
    for (const [target, wire] of wires) {
      const path = cablePath(center(regionNodes.get(graph.links.get(target))), center(wavNodes.get(target)), bounds);
      for (const line of wire.children) line.setAttribute("d", path);
    }
  };

  function dropTarget(x, y) {
    const control = document.elementFromPoint(x, y)?.closest(".wav-node");
    return grid.contains(control) ? control.dataset.targetId : undefined;
  }

  function paintDrag() {
    if (!drag || !grid.isConnected) return;
    const { x, y } = drag;
    const view = viewport.getBoundingClientRect();
    if (x >= view.left && x <= view.right && y >= view.top && y <= view.bottom) {
      if (y - view.top < 24) viewport.scrollTop -= 8;
      else if (view.bottom - y < 24) viewport.scrollTop += 8;
    }
    const target = dropTarget(x, y);
    if (target !== drag.target) {
      wavNodes.get(drag.target)?.control.classList.remove("drop-target");
      wavNodes.get(target)?.control.classList.add("drop-target");
      drag.target = target;
    }
    const end = target ? center(wavNodes.get(target)) : { x, y };
    ghost.setAttribute("d", cablePath(center(regionNodes.get(drag.region)), end, connections.getBoundingClientRect()));
    animation = requestAnimationFrame(paintDrag);
  }

  function stopDrag() {
    if (!drag) return;
    cancelAnimationFrame(animation);
    wavNodes.get(drag.target)?.control.classList.remove("drop-target");
    ghost.removeAttribute("d");
    grid.classList.remove("routing");
    drag = undefined;
  }

  grid.addEventListener("pointermove", (event) => {
    if (drag?.pointerId !== event.pointerId) return;
    drag.x = event.clientX;
    drag.y = event.clientY;
    if (!drag.moved && Math.hypot(drag.x - drag.startX, drag.y - drag.startY) >= 5) {
      drag.moved = true;
      grid.classList.add("routing");
      animation = requestAnimationFrame(paintDrag);
    }
  });
  grid.addEventListener("pointerup", (event) => {
    if (drag?.pointerId !== event.pointerId) return;
    const { region, moved } = drag;
    const target = moved && dropTarget(event.clientX, event.clientY);
    stopDrag();
    if (moved) ignoreClick = region;
    if (target) editRoute(graph, target, region);
  });
  for (const event of ["pointercancel", "lostpointercapture"]) {
    grid.addEventListener(event, (detail) => { if (drag?.pointerId === detail.pointerId) stopDrag(); });
  }
  grid.addEventListener("keydown", (event) => {
    if (state.busy) return;
    if (event.key === "Delete" && graph.selectedTarget) {
      event.preventDefault();
      editRoute(graph, graph.selectedTarget);
    } else if (event.key === "Escape" && (drag || graph.activeRegion || graph.selectedTarget)) {
      event.preventDefault();
      stopDrag();
      selectCable(undefined);
    }
  });
  updateSelection();

  const headings = node("div", "pair-headings", node("h2", "pair-heading", l.regionNodes),
    node("h2", "pair-heading", l.wavNodes));
  return node("div", "route-board", headings, viewport);
}

function transferActions() {
  const l = state.labels;
  const graph = state.transfer?.kind === "regions" ? state.transfer : undefined;
  const plan = graph ? graph.plan : state.transfer;
  const count = graph ? graph.links.size : plan?.rows.length;
  const isReady = state.project.waapi && (!state.syncSamples || Boolean(state.project.samples));
  const levels = !graph && segments("placement", [["same", l.sameLevel], ["parent", l.parentLevel]], state.placement, (value) => {
    state.placement = value;
    state.transfer = undefined;
  });
  if (levels) levels.title = l.newSoundLocation;
  const commands = node("div", "toolbar command-bar",
    button("preview-transfer", l.previewTransfer, () => {
      state.transfer = undefined;
      run("transfer.preview", {
        placement: state.placement, syncSamples: state.syncSamples, renderPreset: state.renderPreset,
      }, l.previewing, (result) => {
        if (result.kind === "regions") result.links = new Map(Object.entries(result.links));
        state.transfer = result;
      });
    }, isReady, !graph && !plan),
    levels,
  );
  const settings = node("div", "control-rack", samplesControls(), renderSetup(undefined, graph));
  const publish = (graph || plan) && button("publish-transfer",
    format(graph ? l.replaceCount : l.transferCount, count), () => {
      if (graph) graph.plan = undefined;
      else state.transfer = undefined;
      run("transfer.publish", { preview: plan.id }, l.transferring, () => {
        state.update = state.transfer = undefined;
      });
    }, isReady && Boolean(plan), true);
  if (graph) {
    const mapping = format(l.pairCount, new Set(graph.links.values()).size, count);
    const clear = button("clear-links", l.clearLinks, () => {
      graph.links.clear();
      graph.activeRegion = graph.selectedTarget = undefined;
      remapRegions(graph, "preview-transfer");
    }, count > 0);
    return [commands, settings, node("section", "route-panel",
      node("div", "route-toolbar", node("div", "route-instructions",
        node("strong", "mapping-count", mapping), node("span", "route-hint", l.pairHint)), clear),
      regionGraph(graph),
      node("div", "transfer-bar", plan?.project && node("span", "transfer-project muted", plan.project), publish),
    )];
  }
  if (!plan) return [commands, settings,
    node("div", "empty-preview", node("p", "hint", state.project.waapi ? l.transferHint : l.needWaapi))];
  const destination = node("div", "destination", node("strong", "", "Wwise"), plan.target,
    node("span", "muted", "Originals / " + plan.folder));
  return [commands, settings, destination, previewTable(plan, "transfer"), node("div", "transfer-bar", publish)];
}

function render(active = document.activeElement?.dataset?.focus) {
  const l = state.labels;
  const scrollable = ".table-wrapper, .graph-wrapper";
  const scroll = app.querySelector(scrollable)?.scrollTop || 0;
  drawConnections = undefined;
  const port = node("input");
  port.type = "number";
  port.min = "1";
  port.max = "65535";
  port.value = state.project.port;
  port.disabled = state.busy;
  port.dataset.focus = "port";
  port.addEventListener("change", () => {
    if (port.valueAsNumber !== state.project.port) run("port.set", { port: port.valueAsNumber }, "", applyProject);
  });

  const mark = node("span", "brand-mark", ...Array.from({ length: 5 }, () => node("i")));
  mark.setAttribute("aria-hidden", "true");
  const projectName = node("div", "project-name", state.project.project);
  projectName.title = l.project + " · " + state.project.project;
  const headline = node("header", "masthead",
    node("div", "brand", mark, node("div", "brand-label", node("h1", "", "PsyReaWwise"), projectName)),
    node("label", "port", l.port, port),
  );
  const tabs = node("nav", "tabs");
  tabs.setAttribute("role", "tablist");
  for (const [value, title] of [["pull", l.pullTab], ["update", l.updateTab], ["transfer", l.transferTab]]) {
    const tab = button("tab-" + value, title, () => { state.tab = value; render(); });
    tab.className = "tab";
    tab.setAttribute("role", "tab");
    tab.setAttribute("aria-selected", String(state.tab === value));
    tabs.append(tab);
  }
  const panels = { pull: pullActions, update: updateActions, transfer: transferActions };
  const panel = node("section", "panel", ...panels[state.tab]());
  panel.setAttribute("role", "tabpanel");
  const message = node("footer", "status" + (state.error ? " error" : state.busy ? " busy" : ""), state.status);
  message.setAttribute("role", "status");
  app.replaceChildren(headline, tabs, panel, message);
  const body = app.querySelector(scrollable);
  if (body) body.scrollTop = scroll;
  if (active) app.querySelector('[data-focus="' + CSS.escape(active) + '"]')?.focus({ preventScroll: true });
  drawConnections?.();
}

window.addEventListener("resize", () => drawConnections?.());

async function start() {
  const capability = await native?.lifecycle?.ready;
  if (capability?.protocol !== 1 || typeof native?.host?.send !== "function" || typeof native?.events?.on !== "function") {
    throw new Error("ReaWebAPI bridge unavailable");
  }
  await native.events.on("message", receive);
  const session = await request("session");
  state.labels = session.labels;
  state.renderPresets = session.renderPresets || [];
  state.presetError = session.presetError;
  applyProject(session.project);
  document.documentElement.lang = session.language === "zh" ? "zh-CN" : "en";
  render();

  for (const [method, value] of [["setDawKeyboard", false], ["setShortcutRouting", false], ["setKeyboardCapture", true]]) {
    if (typeof native.window?.[method] === "function") {
      Promise.resolve().then(() => native.window[method](value)).catch(() => {});
    }
  }
}

function showStartupError() {
  app.replaceChildren(node("div", "startup error",
    "Could not connect to REAPER. Check the ReaWebAPI runtime and reopen this action.",
    node("br"),
    "无法连接到 REAPER。请检查 ReaWebAPI 运行时并重新打开工作台。",
  ));
}

const startupTimeout = setTimeout(showStartupError, 15000);
start().then(() => clearTimeout(startupTimeout), () => {
  clearTimeout(startupTimeout);
  showStartupError();
});
