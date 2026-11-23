// The file on the page: the sample the library builds, parsed by the library
// itself, laid out byte by byte. Two things are drawn here — the ribbon that
// opens the page and the byte map that every record points into.
import { engine, read, bytes, count, value } from "./engine.js";

const eng = await engine();
const ROW = 24;
const MAP_LIMIT = 24 * 512;

/* ——— the ribbon ——————————————————————————————————————————————— */

const ribbon = document.querySelector("[data-ribbon]");
const readout = document.querySelector("[data-readout]");
const sizeLabel = document.querySelector("[data-ribbon-size]");

if (eng && ribbon) {
  const info = read(eng.inspect_hex(eng.sample_file()));
  if (info.ok) {
    paint_ribbon(info);
  }
}

function spans_of(info) {
  return [
    { part: "head", name: "Header", at: 0, length: info.header.length },
    {
      part: "meta",
      name: "Metadata",
      at: info.metadataSpan.at,
      length: info.metadataSpan.length,
    },
    {
      part: "index",
      name: "Tensor index",
      at: info.indexSpan.at,
      length: info.indexSpan.length,
    },
    {
      part: "data",
      name: "Data section",
      at: info.dataStart,
      length: info.bytes - info.dataStart,
    },
  ];
}

function paint_ribbon(info) {
  const spans = spans_of(info);
  sizeLabel.textContent = `${count.format(info.bytes)} bytes · ${info.metadataCount} pairs · ${info.tensorCount} tensors`;
  ribbon.replaceChildren(
    ...spans.map((span) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "seg";
      button.dataset.part = span.part;
      button.style.setProperty("--grow", String(span.length));
      button.style.setProperty("--share", ((span.length / info.bytes) * 100).toFixed(2));
      button.style.setProperty("--tone", `var(--${span.part === "head" ? "head" : span.part})`);
      if (span.length / info.bytes < 0.09) button.classList.add("seg-narrow");
      const pct = ((span.length / info.bytes) * 100).toFixed(1);
      button.innerHTML = `
        <span class="seg-tag"><b>${span.name}</b><span>${count.format(span.length)} B · ${pct}%</span></span>
        <span class="bar"><span class="bar-label">${span.name}</span></span>`;
      const say = () => {
        readout.innerHTML = `<b>${span.name}</b> at byte ${count.format(span.at)} · ${count.format(span.length)} bytes · ${
          span.part === "head"
            ? "magic, version, two counts"
            : span.part === "meta"
              ? `${info.metadataCount} pairs of key and value`
              : span.part === "index"
                ? `${info.tensorCount} entries: name, shape, encoding, offset`
                : "the weights, block after block"
        }`;
      };
      button.addEventListener("pointerenter", say);
      button.addEventListener("focus", say);
      return button;
    }),
  );
  const ticks = document.createElement("div");
  ticks.className = "ribbon-rule";
  for (let i = 0; i <= 4; i += 1) {
    const at = Math.round(info.bytes * (i / 4));
    const tick = document.createElement("span");
    tick.className = "tick";
    tick.style.left = `${(at / info.bytes) * 100}%`;
    tick.textContent = count.format(at);
    ticks.append(tick);
  }
  ribbon.after(ticks);
  readout.innerHTML = `<b>${count.format(info.bytes)}</b> bytes on the sheet · hover or tap a part`;
}

/* ——— the playground ———————————————————————————————————————————— */

const input = document.querySelector("[data-play-input]");
const list = document.querySelector("[data-play-list]");
const verdict = document.querySelector("[data-play-verdict]");
const map = document.querySelector("[data-map]");
const mapNote = document.querySelector("[data-map-note]");
const filePicker = document.querySelector("[data-play-file]");

let timer;
let last = null;

if (eng && input) {
  input.value = eng.sample_file();
  run();
  input.addEventListener("input", () => {
    clearTimeout(timer);
    timer = setTimeout(run, 220);
  });
  document.querySelector("[data-play-run]")?.addEventListener("click", run);
  document.querySelector("[data-play-sample]")?.addEventListener("click", () => {
    input.value = eng.sample_file();
    run();
  });
  filePicker?.addEventListener("change", async () => {
    const file = filePicker.files?.[0];
    if (file) await load(file);
    filePicker.value = "";
  });
  for (const type of ["dragenter", "dragover"]) {
    window.addEventListener(type, (event) => {
      if (!event.dataTransfer?.types.includes("Files")) return;
      event.preventDefault();
      document.body.classList.add("is-dropping");
    });
  }
  for (const type of ["dragleave", "drop"]) {
    window.addEventListener(type, () => document.body.classList.remove("is-dropping"));
  }
  window.addEventListener("drop", async (event) => {
    const file = event.dataTransfer?.files?.[0];
    if (!file) return;
    event.preventDefault();
    await load(file);
  });
}

async function load(file) {
  if (file.size > 128 * 1024) {
    verdict.innerHTML = `<span class="bad">${bytes(file.size)} is too much for the page</span><span>keep it under 128 kB — the index of a model is enough to see its shape</span>`;
    return;
  }
  const buffer = new Uint8Array(await file.arrayBuffer());
  input.value = [...buffer].map((b) => b.toString(16).padStart(2, "0")).join("");
  run();
}

function run() {
  const info = read(eng.inspect_hex(input.value));
  last = info.ok ? info : null;
  const mapCard = map.closest(".map-card");
  if (!info.ok) {
    verdict.innerHTML = `<span class="bad">refused</span><span>${escape(info.error)}</span>`;
    list.innerHTML = '<div class="empty">Nothing was read.</div>';
    map.replaceChildren();
    if (mapNote) mapNote.textContent = "";
    if (mapCard) mapCard.hidden = true;
    return;
  }
  if (mapCard) mapCard.hidden = false;
  verdict.innerHTML = `
    <span><b>${count.format(info.bytes)}</b> bytes</span>
    <span>v<b>${info.version}</b></span>
    <span>${info.endian.toLowerCase()}-endian</span>
    <span><b>${info.metadataCount}</b> pairs</span>
    <span><b>${info.tensorCount}</b> tensors</span>`;
  paint_records(info);
  paint_map(info);
}

function paint_records(info) {
  const parts = [];
  parts.push(section_label("metadata", `${info.metadataCount} pairs`));
  if (!info.metadata.length) {
    parts.push('<div class="empty">No metadata pairs in this file.</div>');
  }
  for (const entry of info.metadata) {
    const node = document.createElement("div");
    node.className = "rec";
    node.dataset.part = "meta";
    node.style.setProperty("--tone", "var(--meta)");
    node.dataset.span = `${entry.offset}:${entry.length}`;
    node.dataset.name = entry.key;
    node.innerHTML = `
      <span class="rec-key">${escape(entry.key)}</span>
      <span class="rec-type">${entry.type === "ARRAY" ? `[${entry.arrayType}]` : entry.type}</span>
      <span class="rec-value">${escape(value(entry.value, entry.type))} <s>· ${count.format(entry.offset)}</s></span>`;
    parts.push(node);
  }
  parts.push(section_label("tensors", `${info.tensorCount} entries`));
  if (!info.tensors.length) {
    parts.push('<div class="empty">No tensors in this file.</div>');
  }
  for (const tensor of info.tensors) {
    const node = document.createElement("div");
    node.className = "rec";
    node.style.setProperty("--tone", "var(--index)");
    node.dataset.part = "index";
    node.dataset.span = `${tensor.infoAt}:${tensor.infoLength}`;
    node.dataset.data = `${tensor.dataAt}:${tensor.length}`;
    node.dataset.name = tensor.name;
    const shape = tensor.dims.join(" × ");
    const perf = (tensor.bytesPerBlock * 8) / tensor.block;
    node.innerHTML = `
      <span class="rec-key">${escape(tensor.name)}</span>
      <span class="rec-type">${tensor.type}</span>
      <span class="rec-value">${shape} · ${count.format(tensor.length)} bytes · ${perf < 10 ? perf.toFixed(2) : perf.toFixed(1)} bits/weight <s>· ${count.format(tensor.dataAt)}</s></span>`;
    parts.push(node);
  }
  list.replaceChildren(...parts);
}

function section_label(name, note) {
  const label = document.createElement("div");
  label.className = "pane-head";
  label.style.userSelect = "none";
  label.innerHTML = `<span>${name}</span><span class="spacer"></span><span>${note}</span>`;
  return label;
}

function paint_map(info) {
  const hex = input.value.replace(/[^0-9a-f]/gi, "");
  const total = info.bytes;
  const shown = Math.min(total, MAP_LIMIT);
  const owner = new Array(shown).fill(null);
  const claim = (at, length, part, record) => {
    for (let i = at; i < Math.min(at + length, shown); i += 1) {
      owner[i] = { part, record };
    }
  };
  claim(0, info.header.length, "head", null);
  for (const entry of info.metadata) claim(entry.offset, entry.length, "meta", entry.key);
  for (const tensor of info.tensors) {
    claim(tensor.infoAt, tensor.infoLength, "index", tensor.name);
    claim(tensor.dataAt, tensor.length, "data", tensor.name);
  }
  // Anything the file does not account for — padding, mostly — is the colour
  // of the part it sits in, which is why the map starts from the records.
  for (let i = 0; i < shown; i += 1) {
    if (owner[i]) continue;
    const part =
      i >= info.dataStart
        ? "data"
        : i >= info.indexSpan.at
          ? "index"
          : i >= info.metadataSpan.at
            ? "meta"
            : "head";
    owner[i] = { part, record: null };
  }

  const rows = [];
  for (let at = 0; at < shown; at += ROW) {
    const row = document.createElement("div");
    row.className = "map-row";
    const gutter = document.createElement("span");
    gutter.className = "map-at";
    gutter.textContent = count.format(at);
    const cells = document.createElement("span");
    cells.className = "map-bytes";
    for (let i = at; i < Math.min(at + ROW, shown); i += 1) {
      const cell = document.createElement("span");
      cell.className = "byte";
      cell.dataset.part = owner[i].part;
      cell.dataset.at = String(i);
      if (owner[i].record) cell.dataset.record = owner[i].record;
      const byte = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
      cell.textContent = byte.toString(16).padStart(2, "0");
      if (byte === 0) cell.classList.add("is-zero");
      cells.append(cell);
    }
    row.append(gutter, cells);
    rows.push(row);
  }
  map.replaceChildren(...rows);
  if (mapNote) {
    mapNote.textContent =
      shown < total
        ? `first ${count.format(shown)} of ${count.format(total)} bytes`
        : `${count.format(total)} bytes, ${ROW} to a row`;
  }
  wire_map();
}

// Pointing at a record lights its bytes, and pointing at a byte lights the
// record it belongs to. One function for both directions, because a reader
// will do both without thinking about which came first.
function wire_map() {
  const records = [...list.querySelectorAll(".rec")];
  const cells = [...map.querySelectorAll(".byte")];
  const light = (name) => {
    for (const cell of cells) {
      cell.classList.toggle("is-lit", cell.dataset.record === name);
    }
    for (const record of records) {
      record.classList.toggle("is-lit", record.dataset.name === name);
    }
  };
  for (const record of records) {
    record.addEventListener("pointerenter", () => {
      const name = record.querySelector(".rec-key").textContent;
      for (const cell of cells) {
        cell.classList.toggle("is-lit", cell.dataset.record === name);
      }
      record.classList.add("is-lit");
    });
    record.addEventListener("pointerleave", () => {
      for (const cell of cells) cell.classList.remove("is-lit");
      record.classList.remove("is-lit");
    });
  }
  for (const cell of cells) {
    cell.addEventListener("pointerenter", () => {
      const name = cell.dataset.record;
      if (!name) return;
      light(name);
    });
    cell.addEventListener("pointerleave", () => {
      for (const other of cells) other.classList.remove("is-lit");
      for (const record of records) record.classList.remove("is-lit");
    });
  }
}

function escape(text) {
  return String(text).replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
  );
}
