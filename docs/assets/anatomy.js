// The anatomy page: one file, drawn to scale, with a head the reader can drag
// through it. Drag follows the pointer exactly, letting go throws it with the
// speed of the throw, and the ends give way rather than stopping dead.
import { engine, read, count, bits, bits_text } from "./engine.js";

const eng = await engine();
const stage = document.querySelector("[data-scan]");
const panel = document.querySelector("[data-scan-panel]");
const lane = document.querySelector("[data-scan-lane]");
const head = document.querySelector("[data-scan-head]");

const ROW = 24;
let info = null;
let hex = "";
let pos = 0;
let raf = 0;

if (eng && stage) {
  hex = eng.sample_file();
  info = read(eng.inspect_hex(hex));
  if (!info.ok) {
    panel.innerHTML = `<div class="empty">${info.error}</div>`;
  } else {
    draw_lane();
    wire_drag();
    wire_steps();
    update();
    paint_chart();
    paint_block();
    paint_kinds();
  }
}

function parts() {
  return [
    {
      part: "head",
      name: "Header",
      at: 0,
      length: info.header.length,
      note: "Magic, version, two counts",
    },
    {
      part: "meta",
      name: "Metadata",
      at: info.metadataSpan.at,
      length: info.metadataSpan.length,
      note: "Key-value pairs, typed",
    },
    {
      part: "index",
      name: "Tensor index",
      at: info.indexSpan.at,
      length: info.indexSpan.length,
      note: "Name, shape, encoding, offset",
    },
    {
      part: "data",
      name: "Data section",
      at: info.dataStart,
      length: info.bytes - info.dataStart,
      note: "The weights themselves",
    },
  ];
}

function draw_lane() {
  const total = info.bytes;
  lane.replaceChildren(
    ...parts().map((span) => {
      const box = document.createElement("div");
      box.className = "lane-seg";
      const width = span.length / total;
      if (width < 0.13) box.classList.add("narrow");
      box.dataset.part = span.part;
      box.style.left = `${(span.at / total) * 100}%`;
      box.style.width = `${width * 100}%`;
      box.innerHTML = `<span>${span.name}</span>`;
      return box;
    }),
  );
}

function wire_drag() {
  let dragging = false;
  let samples = [];
  let frame = 0;

  const at = (clientX) => {
    const box = stage.getBoundingClientRect();
    const raw = ((clientX - box.left) / box.width) * (info.bytes - 1);
    // Past an end, the lane gives way: half the travel, then a quarter.
    if (raw < 0) return raw * 0.35;
    if (raw > info.bytes - 1) return info.bytes - 1 + (raw - (info.bytes - 1)) * 0.35;
    return raw;
  };

  const tick = () => {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(update);
  };

  stage.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 && event.pointerType === "mouse") return;
    dragging = true;
    cancelAnimationFrame(raf);
    cancelAnimationFrame(frame);
    samples = [{ t: performance.now(), x: event.clientX }];
    stage.setPointerCapture(event.pointerId);
    pos = at(event.clientX);
    update();
  });

  stage.addEventListener("pointermove", (event) => {
    if (!dragging) return;
    pos = at(event.clientX);
    const now = performance.now();
    samples.push({ t: now, x: event.clientX });
    samples = samples.filter((s) => now - s.t < 90);
    tick();
  });

  const release = () => {
    if (!dragging) return;
    dragging = false;
    const first = samples[0];
    const last = samples.at(-1);
    let v = 0;
    if (first && last && last.t - first.t > 8) {
      const box = stage.getBoundingClientRect();
      // Bytes per millisecond, the same speed the pointer had.
      v = ((last.x - first.x) / (last.t - first.t)) * ((info.bytes - 1) / box.width);
    }
    if (Math.abs(v) > 0.02) glide(v);
    else snap();
  };

  stage.addEventListener("pointerup", release);
  stage.addEventListener("pointercancel", release);

  stage.addEventListener("keydown", (event) => {
    const step = event.shiftKey ? 256 : 16;
    if (event.key === "ArrowRight") pos = Math.min(info.bytes - 1, pos + step);
    else if (event.key === "ArrowLeft") pos = Math.max(0, pos - step);
    else if (event.key === "Home") pos = 0;
    else if (event.key === "End") pos = info.bytes - 1;
    else return;
    event.preventDefault();
    snap();
    update();
  });

  // A throw keeps its speed and loses it the way a sheet does, then settles on
  // the nearest byte when it runs out or runs into an end.
  function glide(v) {
    cancelAnimationFrame(raf);
    const step = () => {
      pos += v * 16;
      v *= 0.94;
      if (pos < 0 || pos > info.bytes - 1) {
        pos = Math.max(0, Math.min(info.bytes - 1, pos));
        update();
        snap();
        return;
      }
      update();
      if (Math.abs(v) < 0.004) {
        snap();
        return;
      }
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
  }

  // A spring to rest: no overshoot, so the head never wobbles off the byte the
  // reader aimed at.
  function snap() {
    cancelAnimationFrame(raf);
    const target = Math.round(Math.max(0, Math.min(info.bytes - 1, pos)));
    let v = 0;
    let last_t = performance.now();
    const step = (now) => {
      const dt = Math.min(0.032, (now - last_t) / 1000);
      last_t = now;
      const k = 170;
      const c = 26;
      v += (-k * (pos - target) - c * v) * dt;
      pos += v * dt;
      if (Math.abs(pos - target) < 0.4 && Math.abs(v) < 1.5) {
        pos = target;
        update();
        return;
      }
      update();
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
  }

}

// The head, and the panel that says what is under it. One place, because the
// pointer, the keyboard and the momentum all end up here.
function update() {
  head.style.left = `${(Math.max(0, pos) / info.bytes) * 100}%`;
  paint_panel();
}

function owner_of(at) {
  for (const entry of info.metadata) {
    if (at >= entry.offset && at < entry.offset + entry.length) {
      return {
        part: "meta",
        title: entry.key,
        note: `${entry.type === "ARRAY" ? `[${entry.arrayType}]` : entry.type} · ${count.format(entry.length)} bytes`,
        facts: [
          ["field", entry.key],
          ["type", entry.type],
          ["value", short(value_of(entry.value))],
        ],
      };
    }
  }
  for (const tensor of info.tensors) {
    if (at >= tensor.infoAt && at < tensor.infoAt + tensor.infoLength) {
      return {
        part: "index",
        title: tensor.name,
        note: `${tensor.type} · ${tensor.dims.join(" × ")}`,
        facts: [
          ["tensor", tensor.name],
          ["encoding", tensor.type],
          ["shape", tensor.dims.join(" × ")],
          ["data", `at ${count.format(tensor.dataAt)}, ${count.format(tensor.length)} bytes`],
        ],
      };
    }
    if (at >= tensor.dataAt && at < tensor.dataAt + tensor.length) {
      return {
        part: "data",
        title: tensor.name,
        note: `${tensor.type} weights`,
        facts: [
          ["tensor", tensor.name],
          ["block", `${tensor.block} ${tensor.block === 1 ? "value" : "values"} in ${tensor.bytesPerBlock} bytes`],
          ["bits", `${((tensor.bytesPerBlock * 8) / tensor.block).toFixed(2)} per weight`],
        ],
      };
    }
  }
  if (at < info.header.length) {
    const field =
      at < 4
        ? ["magic", "G G U F"]
        : at < 8
          ? ["version", String(info.version)]
          : at < 16
            ? ["tensor count", String(info.tensorCount)]
            : ["metadata count", String(info.metadataCount)];
    return {
      part: "head",
      title: field[0],
      note: `The first ${info.header.length} bytes`,
      facts: [
        ["field", field[0]],
        ["reads", field[1]],
        ["order", info.endian.toLowerCase()],
      ],
    };
  }
  return {
    part: at >= info.dataStart ? "data" : "index",
    title: "padding",
    note: "Alignment bytes, kept so the data section starts on a boundary",
    facts: [["alignment", String(info.alignment)]],
  };
}

function value_of(v) {
  if (Array.isArray(v)) return `${v.length} entries`;
  return String(v);
}

function short(text) {
  return text.length > 34 ? `${text.slice(0, 32)}…` : text;
}

function paint_panel() {
  const at = Math.max(0, Math.min(info.bytes - 1, Math.round(pos)));
  const owner = owner_of(at);
  const part = parts().find((p) => p.part === owner.part) ?? parts()[0];
  const raw = hex.slice(at * 2, at * 2 + 2);
  const window_bytes = [];
  for (let i = Math.max(0, at - 3); i < Math.min(info.bytes, at + 9); i += 1) {
    window_bytes.push({
      at: i,
      text: hex.slice(i * 2, i * 2 + 2),
    });
  }
  panel.style.setProperty("--tone", `var(--${part.part})`);
  mark_key(part.part);
  panel.innerHTML = `
    <div class="scan-part"><span class="swatch swatch-${part.part}"></span>${part.name}</div>
    <div class="scan-what">${escape(owner.title)}<small>${escape(owner.note)}</small></div>
    <div class="scan-bytes">${window_bytes
      .map(
        (b) =>
          `<span class="${b.at === at ? "at" : ""}">${b.text}</span>`,
      )
      .join("")}</div>
    <dl class="scan-facts">
      ${owner.facts
        .map(([k, v]) => `<dt>${escape(k)}</dt><dd>${escape(v)}</dd>`)
        .join("")}
      <dt>offset</dt><dd>${count.format(at)} of ${count.format(info.bytes)}</dd>
      <dt>part</dt><dd>${count.format(part.at)} – ${count.format(part.at + part.length - 1)}</dd>
    </dl>`;
}

// The four parts as buttons: they say how much of the file each one is, and
// take the head there.
function wire_steps() {
  const row = document.querySelector("[data-lane-key]");
  if (!row) return;
  row.replaceChildren(
    ...parts().map((span) => {
      const button = document.createElement("button");
      button.type = "button";
      button.dataset.goto = span.part;
      button.dataset.part = span.part;
      button.setAttribute("aria-pressed", "false");
      button.innerHTML = `<i class="swatch swatch-${span.part}"></i>${span.name} <b>${count.format(span.length)} B</b>`;
      button.addEventListener("click", () => {
        pos = span.at + Math.min(span.length / 2, 8);
        update();
      });
      return button;
    }),
  );
}

// The button whose part the head is standing in.
function mark_key(part) {
  for (const button of document.querySelectorAll("[data-lane-key] button")) {
    button.setAttribute("aria-pressed", button.dataset.goto === part ? "true" : "false");
  }
}

/* ——— the thirteen kinds ————————————————————————————————————————— */

function paint_kinds() {
  const grid = document.querySelector("[data-kinds]");
  if (!grid) return;
  grid.replaceChildren(
    ...read(eng.value_types()).map((kind) => {
      const cell = document.createElement("div");
      cell.className = "kind-cell";
      cell.innerHTML = `<span>${kind.name}</span><b>${kind.code}</b>`;
      return cell;
    }),
  );
}

/* ——— the cost of a weight ——————————————————————————————————————— */

function paint_chart() {
  const chart = document.querySelector("[data-bits]");
  if (!chart) return;
  const rows = read(eng.encodings()).sort((a, b) => bits(b) - bits(a));
  const tally = document.querySelector("[data-bits-count]");
  if (tally) tally.textContent = `${rows.length} encodings, dearest first`;
  const max = Math.max(...rows.map((r) => bits(r)));
  chart.replaceChildren(
    ...rows.map((row) => {
      const line = document.createElement("div");
      line.className = "bit-row";
      line.title = `${row.name}: ${row.block} ${row.block === 1 ? "value" : "values"} in ${row.bytes} bytes`;
      line.innerHTML = `
        <b>${row.name}</b>
        <span class="bit-track"><i style="--fill:${bits(row) / max}"></i></span>
        <span>${bits_text(row)}</span>`;
      return line;
    }),
  );
}

/* ——— one block, drawn ————————————————————————————————————————— */

function paint_block() {
  const select = document.querySelector("[data-block-select]");
  const drawing = document.querySelector("[data-block]");
  const caption = document.querySelector("[data-block-note]");
  if (!select || !drawing) return;
  const rows = read(eng.encodings());
  select.replaceChildren(
    ...rows.map((row) => {
      const option = document.createElement("option");
      option.value = row.name;
      option.textContent = row.name;
      return option;
    }),
  );
  select.value = "Q4_0";
  const draw = () => {
    const row = rows.find((r) => r.name === select.value) ?? rows[0];
    // One square per so many bytes, one dot per so many values, chosen so that
    // both rows stay within about thirty marks and can be compared by length.
    const per_square = Math.max(1, Math.ceil(row.bytes / 30));
    const per_dot = Math.max(1, Math.ceil(row.block / 30));
    const squares = Math.ceil(row.bytes / per_square);
    const dots = Math.ceil(row.block / per_dot);
    drawing.innerHTML = `
      <div class="block-row">
        <span class="block-tag">bytes</span>
        <span class="blocks">${"<i class='value'></i>".repeat(squares)}</span>
      </div>
      <div class="block-row">
        <span class="block-tag">values</span>
        <span class="blocks value-dots">${"<i class='dot'></i>".repeat(dots)}</span>
      </div>`;
    const what = row.block === 1 ? "value" : "values";
    const square = per_square === 1 ? "one byte" : `${per_square} bytes`;
    const dot = per_dot === 1 ? "one value" : `${per_dot} values`;
    caption.innerHTML = `One block of <b>${row.name}</b> holds <b>${row.block}</b> ${what} in <b>${row.bytes}</b> bytes — <b>${bits_text(row)}</b> bits for each weight. A square is ${square}; a dot is ${dot}.`;
  };
  select.addEventListener("change", draw);
  draw();
}

function escape(text) {
  return String(text).replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
  );
}
