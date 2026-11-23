"use strict";

const app = document.getElementById("app");
const pending = new Map();
const state = {
  tab: "transfer",
  mode: "items",
  placement: "same",
  makeRegions: true,
  syncSamples: true,
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

async function run(method, params, progress, apply) {
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
  } catch (error) {
    state.error = true;
    state.status = error.message || state.labels.requestFailed;
  } finally {
    state.busy = false;
    render();
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
  const toggle = node("label", "toggle sync-toggle", check, l.syncSamples);
  if (!state.syncSamples) return node("div", "folder-control", toggle);

  return node("div", "folder-control", toggle,
    node("span", "folder-name muted", state.project.samples || l.samplesHint),
    button("samples-choose", l.samplesChoose, () => run("samples.choose", {}, l.choosing)),
    state.project.customSamples
      ? button("samples-default", l.samplesDefault, () => run("samples.reset", {}, l.choosing))
      : undefined,
  );
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
      run("update.preview", { mode: state.mode, syncSamples: state.syncSamples }, l.checking, (result) => {
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
  return [samplesControls(), commands, node("p", "hint", hint), plan && previewTable(plan, "update")];
}

function remapRegions(graph) {
  graph.plan = undefined;
  run("transfer.map", { draft: graph.draft, links: graph.links, syncSamples: state.syncSamples }, "", (result) => {
    if (state.transfer === graph) graph.plan = result.plan;
  });
}

function regionGraph(graph) {
  const l = state.labels;
  const regions = node("div", "pair-column", node("h2", "pair-heading", l.regionNodes));
  const wavs = node("div", "pair-column", node("h2", "pair-heading", l.wavNodes));
  const regionPorts = new Map();
  const wavPorts = new Map();
  const wavById = new Map(graph.targets.map((target) => [target.id, target]));
  const linkedRegions = new Map(Object.entries(graph.links).map(([region, wav]) => [wav, region]));
  const previewRows = new Map((graph.plan?.rows || []).map((row) => [row.targetId, row]));

  for (const region of graph.regions) {
    const linked = wavById.get(graph.links[region.id]);
    const nextName = linked?.name.replace(/\.wav$/i, "");
    const rename = nextName && nextName !== region.name ? format(l.renameTo, nextName) : "";
    const name = region.name || l.unnamedRegion;
    const control = button("region-node-" + region.id, "", () => {
      graph.activeRegion = graph.activeRegion === region.id ? undefined : region.id;
      render();
    }, region.renderable);
    control.className = "pair-node";
    control.title = rename ? name + "\n" + rename : name;
    control.dataset.linked = String(Boolean(linked));
    control.setAttribute("aria-pressed", String(graph.activeRegion === region.id));
    const port = node("span", "pair-port");
    port.setAttribute("aria-hidden", "true");
    regionPorts.set(region.id, port);
    control.append(node("span", "pair-title", name),
      node("span", "pair-detail", "R" + region.number + (rename ? " · " + rename : "")), port);
    regions.append(control);
  }

  for (const target of graph.targets) {
    const owner = linkedRegions.get(target.id);
    const row = previewRows.get(target.id);
    const control = button("wav-node-" + target.id, "", () => {
      const region = graph.activeRegion || owner;
      if (!graph.activeRegion) {
        graph.activeRegion = region;
        render();
        return;
      }
      if (owner) delete graph.links[owner];
      if (owner !== region) graph.links[region] = target.id;
      graph.activeRegion = undefined;
      remapRegions(graph);
    }, Boolean(graph.activeRegion || owner));
    control.className = "pair-node wav-node";
    control.title = [target.originalsPath, ...(row?.references || []), row?.sample].filter(Boolean).join("\n");
    control.dataset.linked = String(Boolean(owner));
    const port = node("span", "pair-port");
    port.setAttribute("aria-hidden", "true");
    wavPorts.set(target.id, port);
    const directory = target.originals.replace(/[\\/][^\\/]+$/, "");
    const shared = target.references > 1 ? l.shared : "";
    control.append(node("span", "pair-title", target.name), node("span", "pair-detail", directory + shared));
    if (row?.sample) control.append(node("span", "pair-detail", "Samples · " + (row.replace ? l.replace : l.add)));
    control.append(port);
    wavs.append(control);
  }

  const svgNamespace = "http://www.w3.org/2000/svg";
  const connections = document.createElementNS(svgNamespace, "svg");
  connections.classList.add("pair-connections");
  connections.setAttribute("aria-hidden", "true");
  drawConnections = () => {
    const bounds = connections.getBoundingClientRect();
    const paths = [];
    for (const [region, wav] of Object.entries(graph.links)) {
      const from = regionPorts.get(region).getBoundingClientRect();
      const to = wavPorts.get(wav).getBoundingClientRect();
      const x1 = from.left + from.width / 2 - bounds.left;
      const x2 = to.left + to.width / 2 - bounds.left;
      const y1 = from.top + from.height / 2 - bounds.top;
      const y2 = to.top + to.height / 2 - bounds.top;
      const center = (x1 + x2) / 2;
      const path = document.createElementNS(svgNamespace, "path");
      path.setAttribute("d", "M " + x1 + " " + y1 + " C " + center + " " + y1 + " " + center + " " + y2 + " " + x2 + " " + y2);
      if (region === graph.activeRegion) path.classList.add("active");
      paths.push(path);
    }
    connections.replaceChildren(...paths);
  };
  return node("div", "graph-wrapper", node("div", "pair-grid", regions, wavs, connections));
}

function transferActions() {
  const l = state.labels;
  const graph = state.transfer?.kind === "regions" ? state.transfer : undefined;
  const plan = graph ? graph.plan : state.transfer;
  const count = graph ? Object.keys(graph.links).length : plan?.rows.length;
  const isReady = state.project.waapi && (!state.syncSamples || Boolean(state.project.samples));
  const levels = !graph && segments("placement", [["same", l.sameLevel], ["parent", l.parentLevel]], state.placement, (value) => {
    state.placement = value;
    state.transfer = undefined;
  });
  if (levels) levels.title = l.newSoundLocation;
  const commands = node("div", "toolbar", levels,
    button("preview-transfer", l.previewTransfer, () => {
      state.transfer = undefined;
      run("transfer.preview", { placement: state.placement, syncSamples: state.syncSamples }, l.previewing, (result) => {
        if (result.kind === "regions") result.links = { ...result.links };
        state.transfer = result;
      });
    }, isReady),
    (graph || plan) && node("div", "actions", button("publish-transfer", format(graph ? l.replaceCount : l.transferCount, count), () => {
      state.transfer = undefined;
      run("transfer.publish", { preview: plan.id }, l.transferring, () => { state.update = undefined; });
    }, isReady && Boolean(plan), true)),
  );
  if (graph) return [samplesControls(), commands,
    node("div", "pair-summary", node("strong", "", format(l.pairCount, count, graph.regions.length)),
      node("span", "muted", l.pairHint)),
    regionGraph(graph)];
  if (!plan) return [samplesControls(), commands,
    node("p", "hint", state.project.waapi ? l.transferHint : l.needWaapi)];
  const destination = node("div", "destination", node("strong", "", "Wwise"), plan.target,
    node("span", "muted", "Originals / " + plan.folder));
  return [samplesControls(), commands, destination, previewTable(plan, "transfer")];
}

function render() {
  const l = state.labels;
  const active = document.activeElement?.dataset?.focus;
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

  const headline = node("header", "masthead",
    node("div", "", node("h1", "", "PsyReaWwise WebView"), node("div", "project-name", l.project + " · " + state.project.project)),
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
