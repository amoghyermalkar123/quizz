const DEMO_REPORT = {
  trace_demo: [
    {
      state_index: 0,
      action: "init",
      matched: true,
      spec_state: {
        coordinator: "n1",
        phase: { n1: "Idle", n2: "Idle", n3: "Idle" },
        logIndex: { n1: 0, n2: 0, n3: 0 },
      },
      driver_state: {
        coordinator: "n1",
        phase: { n1: "Idle", n2: "Idle", n3: "Idle" },
        logIndex: { n1: 0, n2: 0, n3: 0 },
      },
    },
    {
      state_index: 1,
      action: "prepare",
      matched: true,
      spec_state: {
        coordinator: "n1",
        phase: { n1: "Preparing", n2: "Prepared", n3: "Prepared" },
        logIndex: { n1: 1, n2: 1, n3: 1 },
      },
      driver_state: {
        coordinator: "n1",
        phase: { n1: "Preparing", n2: "Prepared", n3: "Prepared" },
        logIndex: { n1: 1, n2: 1, n3: 1 },
      },
    },
    {
      state_index: 2,
      action: "commit",
      matched: false,
      spec_state: {
        coordinator: "n1",
        phase: { n1: "Committed", n2: "Committed", n3: "Committed" },
        logIndex: { n1: 2, n2: 2, n3: 2 },
      },
      driver_state: {
        coordinator: "n1",
        phase: { n1: "Committed", n2: "Prepared", n3: "Committed" },
        logIndex: { n1: 2, n2: 1, n3: 2 },
      },
    },
    {
      state_index: 3,
      action: "apply",
      matched: false,
      spec_state: {
        coordinator: "n1",
        phase: { n1: "Applied", n2: "Applied", n3: "Applied" },
        logIndex: { n1: 2, n2: 2, n3: 2 },
      },
      driver_state: {
        coordinator: "n1",
        phase: { n1: "Applied", n2: "Prepared", n3: "Applied" },
        logIndex: { n1: 2, n2: 1, n3: 2 },
      },
    },
  ],
};

const appState = {
  trace: null,
  currentStep: 0,
  isPlaying: false,
  playbackMs: 1000,
  timerId: null,
  compareScroll: {
    topRatio: 0,
    leftRatio: 0,
    syncing: false,
  },
};

const els = {
  traceFile: document.querySelector("#trace-file"),
  resetDemo: document.querySelector("#reset-demo"),
  playToggle: document.querySelector("#play-toggle"),
  stepBack: document.querySelector("#step-back"),
  stepForward: document.querySelector("#step-forward"),
  stepRange: document.querySelector("#step-range"),
  playbackSpeed: document.querySelector("#playback-speed"),
  traceSummary: document.querySelector("#trace-summary"),
  eventStream: document.querySelector("#event-stream"),
  eventCount: document.querySelector("#event-count"),
  eventTitle: document.querySelector("#event-title"),
  eventBadges: document.querySelector("#event-badges"),
  behaviorCanvas: document.querySelector("#behavior-canvas"),
  transitionSummary: document.querySelector("#transition-summary"),
  nondetPicks: document.querySelector("#nondet-picks"),
};

function init() {
  bindEvents();
  loadDefaultReport();
}

function bindEvents() {
  els.playToggle.addEventListener("click", togglePlayback);
  els.stepBack.addEventListener("click", () => {
    stopPlayback();
    setCurrentStep(appState.currentStep - 1);
  });
  els.stepForward.addEventListener("click", () => {
    stopPlayback();
    setCurrentStep(appState.currentStep + 1);
  });
  els.stepRange.addEventListener("input", (event) => {
    stopPlayback();
    setCurrentStep(Number(event.target.value));
  });
  els.playbackSpeed.addEventListener("change", (event) => {
    appState.playbackMs = Number(event.target.value);
    if (appState.isPlaying) {
      stopPlayback();
      startPlayback();
    }
  });
  els.traceFile.addEventListener("change", async (event) => {
    const [file] = event.target.files || [];
    if (!file) return;

    try {
      const text = await file.text();
      loadTrace(JSON.parse(text), file.name);
    } catch (error) {
      stopPlayback();
      window.alert(`Could not parse trace file: ${error.message}`);
    } finally {
      event.target.value = "";
    }
  });
  els.resetDemo.addEventListener("click", () => {
    stopPlayback();
    loadDefaultReport();
  });
}

async function loadDefaultReport() {
  try {
    const response = await fetch("../../quizz_run.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    loadTrace(await response.json(), "quizz_run.json");
  } catch (error) {
    console.warn("Falling back to embedded demo report:", error);
    loadTrace(DEMO_REPORT, "quizz_run.json");
  }
}

function loadTrace(rawTrace, sourceLabel = "trace") {
  appState.trace = buildTraceModel(rawTrace, sourceLabel);
  appState.currentStep = findPreferredStep(appState.trace.steps);
  appState.compareScroll.topRatio = 0;
  appState.compareScroll.leftRatio = 0;
  els.stepRange.max = String(Math.max(appState.trace.steps.length - 1, 0));
  els.stepRange.value = String(appState.currentStep);
  render();
}

function buildTraceModel(rawTrace, sourceLabel) {
  if (isReplayReport(rawTrace)) {
    return buildReplayReportModel(rawTrace, sourceLabel);
  }

  return buildItfTraceModel(rawTrace, sourceLabel);
}

function isReplayReport(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return false;
  return Object.values(raw).some(
    (value) =>
      Array.isArray(value) &&
      value.length > 0 &&
      value.every((entry) => entry && typeof entry === "object" && "spec_state" in entry && "driver_state" in entry),
  );
}

function buildReplayReportModel(rawReport, sourceLabel) {
  const entries = Object.entries(rawReport)
    .filter(([, value]) => Array.isArray(value))
    .sort(([leftKey], [rightKey]) => traceKeyOrder(leftKey) - traceKeyOrder(rightKey));

  const steps = [];
  entries.forEach(([traceKey, records], traceOrder) => {
    records.forEach((record, indexInTrace) => {
      steps.push({
        traceKey,
        traceOrder,
        index: typeof record.state_index === "number" ? record.state_index : indexInTrace,
        replayIndex: steps.length,
        action: record.action || `step-${indexInTrace}`,
        matched: record.matched !== false,
        specState: normalizePlainJson(record.spec_state),
        driverState: normalizePlainJson(record.driver_state),
        state: normalizePlainJson(record.spec_state),
        nondet: {},
      });
    });
  });

  return {
    kind: "report",
    meta: {
      format: "QUIZZ_RUN",
      source: sourceLabel,
      status: steps.some((step) => !step.matched) ? "failed" : "ok",
      description: `${steps.length} replay steps across ${entries.length} traces`,
      traceKey: entries[0]?.[0] || sourceLabel,
      traceCount: entries.length,
    },
    steps,
  };
}

function buildItfTraceModel(rawTrace, sourceLabel) {
  const steps = (rawTrace.states || []).map((rawState, index) => {
    const meta = rawState["#meta"] || {};
    const values = {};

    Object.entries(rawState).forEach(([key, value]) => {
      if (key === "#meta") return;
      values[key] = normalizeItfValue(value);
    });

    const action = String(values["mbt::actionTaken"] ?? `step-${index}`);
    const nondet = values["mbt::nondetPicks"] || {};
    const specState = Object.fromEntries(
      Object.entries(values).filter(([key]) => !key.startsWith("mbt::")),
    );

    return {
      index: typeof meta.index === "number" ? meta.index : index,
      action,
      matched: null,
      specState,
      driverState: null,
      state: specState,
      nondet,
    };
  });

  const markers = steps
    .filter((step, index) => isActionBoundary(step, steps[index - 1]))
    .map((step, index) => ({
      index: step.index,
      label: humanizeAction(step.action),
      caption: index === 0 ? "Initial snapshot" : "Spec transition",
    }));

  return {
    kind: "itf",
    meta: {
      format: rawTrace["#meta"]?.format || "ITF",
      source: rawTrace["#meta"]?.source || sourceLabel,
      status: rawTrace["#meta"]?.status || "unknown",
      description: rawTrace["#meta"]?.description || "ITF replay trace",
      traceKey: sourceLabel,
    },
    steps,
    markers,
  };
}

function normalizePlainJson(value) {
  if (Array.isArray(value)) return value.map(normalizePlainJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, nested]) => [key, normalizePlainJson(nested)]));
  }
  return value;
}

function normalizeItfValue(value) {
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map(normalizeItfValue);
  if ("#bigint" in value) return value["#bigint"];
  if ("#tup" in value) return value["#tup"].map(normalizeItfValue);
  if ("#set" in value) return value["#set"].map(normalizeItfValue);
  if ("#map" in value) {
    return Object.fromEntries(
      value["#map"].map(([key, nested]) => [String(normalizeItfValue(key)), normalizeItfValue(nested)]),
    );
  }
  if ("tag" in value && "value" in value) {
    if (value.tag === "Some") return normalizeItfValue(value.value);
    if (value.tag === "None") return null;
    return { [value.tag]: normalizeItfValue(value.value) };
  }
  if ("#unserializable" in value) return value["#unserializable"];
  return Object.fromEntries(Object.entries(value).map(([key, nested]) => [key, normalizeItfValue(nested)]));
}

function isActionBoundary(step, previous) {
  if (!previous) return true;
  return step.action !== previous.action;
}

function findPreferredStep(steps) {
  return steps.length ? 0 : 0;
}

function render() {
  if (!appState.trace) return;

  const step = appState.trace.steps[appState.currentStep];
  const previous = getPreviousReplayStep(appState.currentStep);

  renderSummary();
  renderEventStream(appState.currentStep);
  renderStateCompare(step, previous);
  renderInspector(step, previous);
  renderMeta(step);

  els.stepRange.value = String(appState.currentStep);
}

function renderSummary() {
  const { meta, steps } = appState.trace;
  const rows = [
    ["Format", meta.format],
    ["Traces", String(meta.traceCount || 1)],
    ["Trace", currentTraceLabel()],
    ["Source", meta.source],
    ["States", String(steps.length)],
    ["Status", meta.status],
  ];

  els.traceSummary.innerHTML = rows
    .map(([label, value]) => `<dt>${escapeHtml(label)}</dt><dd>${escapeHtml(String(value))}</dd>`)
    .join("");
  els.eventCount.textContent = `${steps.length} events`;
}

function renderEventStream(currentIndex) {
  els.eventStream.innerHTML = appState.trace.steps
    .map((step, replayIndex) => {
      const active = replayIndex === currentIndex ? "active" : "";
      const status = step.matched === false ? "Mismatch" : step.matched === true ? "Match" : "Spec";
      return `
        <li>
          <button class="event-button ${active}" type="button" data-step="${replayIndex}">
            <strong>${escapeHtml(step.traceKey ? `${step.traceKey} · ${humanizeAction(step.action)}` : humanizeAction(step.action))}</strong>
            <span>${escapeHtml(`state ${String(step.index).padStart(2, "0")} · ${status}`)}</span>
          </button>
        </li>
      `;
    })
    .join("");

  els.eventStream.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => setCurrentStep(Number(button.dataset.step)));
  });
}

function renderStateCompare(step, previous) {
  const leftState = step.driverState ? step.specState : previous?.specState;
  const rightState = step.driverState ? step.driverState : step.specState;
  const diff = leftState && rightState ? computeDiff(leftState, rightState) : { changed: [], all: [] };
  const leftTitle = step.driverState ? "Spec state" : "Previous spec state";
  const rightTitle = step.driverState ? "Driver state" : "Current spec state";
  const highlight = buildHighlightSets(diff.changed);

  els.behaviorCanvas.innerHTML = `
    <div class="compare-summary fade-in">
      <div>
        <p class="eyebrow">Selected action</p>
        <h3>${escapeHtml(humanizeAction(step.action))}</h3>
      </div>
      <div class="compare-summary-meta">
        <span class="pill ${step.matched === false ? "warn" : ""}">
          ${escapeHtml(step.matched === false ? "Mismatch detected" : step.matched === true ? "Spec and driver match" : "Driver snapshot unavailable")}
        </span>
        <span class="pill">${escapeHtml(`${diff.changed.length} differing paths`)}</span>
      </div>
    </div>
    <div class="compare-grid">
      <section class="compare-card">
        <header><strong>${escapeHtml(leftTitle)}</strong></header>
        <div class="json-viewer" data-compare-pane="left">${renderStatePane(leftState, "", highlight)}</div>
      </section>
      <section class="compare-card">
        <header><strong>${escapeHtml(rightTitle)}</strong></header>
        <div class="json-viewer" data-compare-pane="right">${renderStatePane(rightState, "", highlight)}</div>
      </section>
    </div>
  `;

  bindComparePaneSync();
}

function renderInspector(step, previous) {
  const specDriverDiff = step.driverState ? computeDiff(step.specState, step.driverState).changed.length : null;
  const prevSpecDiff = previous ? computeDiff(previous.specState, step.specState).changed.length : 0;

  els.transitionSummary.innerHTML = `
    <div class="summary-banner fade-in">
      <h3>${escapeHtml(humanizeAction(step.action))}</h3>
      <p class="muted-copy">Trace ${escapeHtml(step.traceKey || currentTraceLabel())} · step ${step.index}.</p>
      <p class="muted-copy">${
        specDriverDiff !== null
          ? `${specDriverDiff} spec/driver diffs at this action.`
          : `${prevSpecDiff} spec-state changes from the previous action.`
      }</p>
    </div>
  `;

  const details = [
    { label: "Trace source", value: appState.trace.meta.source },
    { label: "Trace id", value: step.traceKey || currentTraceLabel() },
    { label: "Action", value: humanizeAction(step.action) },
    { label: "Step index", value: String(step.index) },
    { label: "Replay index", value: String(appState.currentStep) },
  ];

  if (step.matched !== null) {
    details.push({ label: "Match status", value: step.matched ? "Matched" : "Mismatch" });
  }

  els.nondetPicks.innerHTML = details
    .map(
      (entry) => `
        <div class="inspector-entry fade-in">
          <strong>${escapeHtml(entry.label)}</strong>
          <pre>${escapeHtml(entry.value)}</pre>
        </div>
      `,
    )
    .join("");
}


function renderMeta(step) {
  const diffCount = step.driverState ? computeDiff(step.specState, step.driverState).changed.length : 0;
  els.eventTitle.textContent = `${step.traceKey ? `${step.traceKey} · ` : ""}${humanizeAction(step.action)} · step ${step.index}`;
  els.eventBadges.innerHTML = `
    <span class="pill">${escapeHtml(step.traceKey || currentTraceLabel())}</span>
    <span class="pill">${escapeHtml(step.matched === false ? "Mismatch" : step.matched === true ? "Matched" : "Spec only")}</span>
    <span class="pill">${escapeHtml(`${diffCount} differing paths`)}</span>
  `;
}

function getPreviousReplayStep(currentReplayIndex) {
  const previous = appState.trace.steps[currentReplayIndex - 1] || null;
  if (!previous) return null;
  const current = appState.trace.steps[currentReplayIndex];
  if (!current) return previous;
  return previous.traceKey === current.traceKey ? previous : null;
}

function currentTraceLabel() {
  const current = appState.trace?.steps?.[appState.currentStep];
  return current?.traceKey || appState.trace?.meta?.traceKey || shortFileName(appState.trace?.meta?.source || "trace");
}

function traceKeyOrder(traceKey) {
  const match = /^trace_(\d+)$/.exec(String(traceKey));
  return match ? Number(match[1]) : Number.MAX_SAFE_INTEGER;
}

function bindComparePaneSync() {
  const panes = [...els.behaviorCanvas.querySelectorAll(".json-viewer")];
  if (panes.length !== 2) return;

  restoreComparePaneScroll(panes);

  panes.forEach((pane, index) => {
    pane.addEventListener("scroll", () => {
      if (appState.compareScroll.syncing) return;

      const target = panes[index === 0 ? 1 : 0];
      if (!target) return;

      appState.compareScroll.topRatio = scrollRatio(pane.scrollTop, pane.scrollHeight - pane.clientHeight);
      appState.compareScroll.leftRatio = scrollRatio(pane.scrollLeft, pane.scrollWidth - pane.clientWidth);

      appState.compareScroll.syncing = true;
      target.scrollTop = appState.compareScroll.topRatio * Math.max(target.scrollHeight - target.clientHeight, 0);
      target.scrollLeft = appState.compareScroll.leftRatio * Math.max(target.scrollWidth - target.clientWidth, 0);
      appState.compareScroll.syncing = false;
    });
  });
}

function restoreComparePaneScroll(panes) {
  panes.forEach((pane) => {
    pane.scrollTop = appState.compareScroll.topRatio * Math.max(pane.scrollHeight - pane.clientHeight, 0);
    pane.scrollLeft = appState.compareScroll.leftRatio * Math.max(pane.scrollWidth - pane.clientWidth, 0);
  });
}

function scrollRatio(offset, maxOffset) {
  if (maxOffset <= 0) return 0;
  return offset / maxOffset;
}

function computeDiff(beforeState = {}, afterState = {}) {
  const beforeFlat = flattenState(beforeState);
  const afterFlat = flattenState(afterState);
  const allPaths = Array.from(new Set([...Object.keys(beforeFlat), ...Object.keys(afterFlat)])).sort();
  const all = allPaths.map((path) => {
    const before = beforeFlat[path] ?? "—";
    const after = afterFlat[path] ?? "—";
    const kind = before === after ? "stable" : before === "—" ? "added" : after === "—" ? "removed" : "changed";
    return { path, before, after, kind };
  });

  return { all, changed: all.filter((row) => row.kind !== "stable") };
}

function buildHighlightSets(changedRows) {
  const exact = new Set();
  const ancestors = new Set();

  changedRows.forEach((row) => {
    exact.add(row.path);
    const parts = row.path.split(".");
    for (let index = 1; index < parts.length; index += 1) {
      ancestors.add(parts.slice(0, index).join("."));
    }
  });

  return { exact, ancestors };
}

function renderStatePane(value, path, highlight, depth = 0) {
  if (value === null || value === undefined || Array.isArray(value) || typeof value !== "object") {
    return renderJsonLine(path, depth, formatJsonLiteral(value), highlight);
  }

  const entries = Object.entries(value);
  if (!entries.length) {
    return renderJsonLine(path, depth, "{}", highlight);
  }

  const open = `
    <div class="json-line ${jsonLineClass(path, highlight)}" style="--indent:${depth * 16}px">
      <span class="json-brace">{</span>
    </div>
  `;
  const body = entries
    .map(([key, nested]) => renderJsonEntry(key, nested, path ? `${path}.${key}` : key, highlight, depth + 1))
    .join("");
  const close = `
    <div class="json-line ${jsonLineClass(path, highlight)}" style="--indent:${depth * 16}px">
      <span class="json-brace">}</span>
    </div>
  `;

  return `${open}${body}${close}`;
}

function renderJsonLine(path, depth, content, highlight, raw = false) {
  return `
    <div class="json-line ${jsonLineClass(path, highlight)}" style="--indent:${depth * 16}px">
      ${raw ? content : escapeHtml(content)}
    </div>
  `;
}

function renderJsonEntry(key, value, path, highlight, depth) {
  const keyMarkup = `<span class="json-key">"${escapeHtml(key)}"</span>: `;

  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    return `
      <div class="json-line ${jsonLineClass(path, highlight)}" style="--indent:${depth * 16}px">
        ${keyMarkup}<span class="json-brace">{</span>
      </div>
      ${Object.entries(value)
        .map(([childKey, childValue]) =>
          renderJsonEntry(childKey, childValue, `${path}.${childKey}`, highlight, depth + 1),
        )
        .join("")}
      <div class="json-line ${jsonLineClass(path, highlight)}" style="--indent:${depth * 16}px">
        <span class="json-brace">}</span>
      </div>
    `;
  }

  return renderJsonLine(path, depth, `${keyMarkup}<span class="json-value">${escapeHtml(formatJsonLiteral(value))}</span>`, highlight, true);
}

function jsonLineClass(path, highlight) {
  if (!path) return "";
  if (highlight.exact.has(path)) return "changed";
  if (highlight.ancestors.has(path)) return "changed-ancestor";
  return "";
}

function flattenState(value, prefix = "", output = {}) {
  if (value === null || value === undefined) {
    output[prefix || "(root)"] = "null";
    return output;
  }

  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    output[prefix || "(root)"] = String(value);
    return output;
  }

  if (Array.isArray(value)) {
    output[prefix || "(root)"] = `[${value.map((item) => renderScalar(item)).join(", ")}]`;
    return output;
  }

  Object.entries(value).forEach(([key, nested]) => {
    flattenState(nested, `${prefix}.${key}`.replace(/^\./, ""), output);
  });

  return output;
}

function renderJsonBlock(value) {
  if (value === null || value === undefined) return "No state available.";
  return JSON.stringify(value, null, 2);
}

function formatJsonLiteral(value) {
  if (value === null || value === undefined) return "null";
  if (Array.isArray(value)) return JSON.stringify(value);
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function renderScalar(value) {
  return typeof value === "string" ? value : JSON.stringify(value);
}

function valueTypeLabel(value) {
  if (Array.isArray(value)) return "Array";
  if (value === null) return "Null";
  if (typeof value === "object") return "Object";
  return typeof value;
}

function humanizeAction(action) {
  return String(action)
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/[_:]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function shortFileName(path) {
  const parts = String(path).split("/");
  return parts[parts.length - 1];
}

function setCurrentStep(nextIndex) {
  const bounded = Math.max(0, Math.min(appState.trace.steps.length - 1, nextIndex));
  appState.currentStep = bounded;
  render();
}

function togglePlayback() {
  if (appState.isPlaying) {
    stopPlayback();
    return;
  }
  startPlayback();
}

function startPlayback() {
  appState.isPlaying = true;
  els.playToggle.textContent = "Pause";
  appState.timerId = window.setInterval(() => {
    if (appState.currentStep >= appState.trace.steps.length - 1) {
      stopPlayback();
      return;
    }
    setCurrentStep(appState.currentStep + 1);
  }, appState.playbackMs);
}

function stopPlayback() {
  appState.isPlaying = false;
  els.playToggle.textContent = "Play";
  if (appState.timerId) {
    window.clearInterval(appState.timerId);
    appState.timerId = null;
  }
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

init();
