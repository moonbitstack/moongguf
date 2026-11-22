// The catalogue: every encoding the library knows, as cards a reader can sort
// with their eyes. Filtering is a matter of hiding cards, and the numbers on
// them come from the library rather than from this file.
import { engine, read, bits, bits_text, count } from "./engine.js";

const grid = document.querySelector("[data-catalogue]");
if (grid) {
  const eng = await engine();
  const chips = [...document.querySelectorAll("[data-filter-enc]")];
  const search = document.querySelector("[data-search-enc]");
  const tally = document.querySelector("[data-enc-count]");
  let rows = [];

  if (!eng) {
    grid.innerHTML =
      '<div class="empty">The library is built for this page by the docs workflow; it is not here yet.</div>';
  } else {
    rows = read(eng.encodings());
    const stats = {
      encodings: rows.length,
      kinds: read(eng.value_types()).length,
    };
    for (const node of document.querySelectorAll("[data-stat]")) {
      node.textContent = stats[node.dataset.stat] ?? "—";
    }
    rows.sort((a, b) => a.code - b.code);
    // Measured against an f32 weight, which is what a reader compares with:
    // the bar is how much smaller than four bytes a value has become.
    const full = 32;
    const cards = new Map();

    for (const row of rows) {
      const card = document.createElement("button");
      card.className = "enc";
      card.type = "button";
      card.dataset.name = row.name.toLowerCase();
      card.dataset.group = group_of(row);
      card.setAttribute("aria-expanded", "false");
      card.innerHTML = `
        <span class="enc-name">${row.name}<small>code ${row.code}</small></span>
        <span class="enc-bits">${bits_text(row)}<span>bits / weight</span></span>
        <span class="enc-meter"><i style="--fill:0"></i></span>
        <span class="enc-foot"><span>block ${row.block}</span><span>${row.bytes} B / block</span></span>`;
      card.querySelector(".enc-meter i").style.setProperty(
        "--fill",
        String(Math.min(1, bits(row) / full)),
      );
      card.addEventListener("click", () => toggle(card, row));
      grid.append(card);
      cards.set(row.name, card);
    }

    for (const chip of chips) {
      chip.addEventListener("click", () => {
        for (const other of chips) other.setAttribute("aria-pressed", "false");
        chip.setAttribute("aria-pressed", "true");
        apply();
      });
    }
    search?.addEventListener("input", apply);
    search?.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      search.value = "";
      apply();
    });

    apply();

    function apply() {
      const group = chips.find((c) => c.getAttribute("aria-pressed") === "true")
        ?.dataset.filterEnc;
      const needle = (search?.value ?? "").trim().toLowerCase();
      let shown = 0;
      for (const row of rows) {
        const card = cards.get(row.name);
        const hit =
          (!group || group === "all" || card.dataset.group === group) &&
          (!needle ||
            row.name.toLowerCase().includes(needle) ||
            String(row.code) === needle);
        card.hidden = !hit;
        if (hit) shown += 1;
        else if (card.getAttribute("aria-expanded") === "true") toggle(card, row);
      }
      if (tally) {
        tally.textContent = `${shown} of ${rows.length} encodings`;
      }
      const empty = grid.querySelector(".no-hit");
      if (shown === 0 && !empty) {
        const note = document.createElement("div");
        note.className = "empty no-hit";
        note.textContent = "Nothing by that name. Try a prefix, or clear the filter.";
        grid.append(note);
      } else if (shown > 0) {
        empty?.remove();
      }
    }

    function toggle(card, row) {
      const open = card.getAttribute("aria-expanded") === "true";
      grid.querySelector(".enc-detail")?.remove();
      for (const other of cards.values()) {
        other.setAttribute("aria-expanded", "false");
      }
      if (open) return;
      card.setAttribute("aria-expanded", "true");
      const detail = document.createElement("div");
      detail.className = "enc-detail";
      const per_megabyte = Math.floor((1024 * 1024 * 8) / bits(row));
      detail.innerHTML = `
        <div>
          <h4>${row.name}</h4>
          <p>${
            row.quantized
              ? `One block holds ${row.block} values in ${row.bytes} bytes, so a weight costs ${bits_text(row)} bits. A megabyte of these holds about ${count.format(per_megabyte)} weights.`
              : `One value to a block, ${row.bytes} bytes each: nothing is packed. A megabyte holds ${count.format(per_megabyte)} values.`
          }</p>
        </div>
        <dl>
          <dt>number</dt><dd>${row.code}</dd>
          <dt>block</dt><dd>${row.block} ${row.block === 1 ? "value" : "values"}</dd>
          <dt>bytes</dt><dd>${row.bytes} per block</dd>
          <dt>bits</dt><dd>${bits_text(row)} per weight</dd>
        </dl>`;
      // Below the row the card is in, not below the card: a card in the middle
      // of a row would otherwise leave the rest of that row empty.
      const all = [...grid.querySelectorAll(".enc")];
      const per_row = Math.max(
        1,
        getComputedStyle(grid).gridTemplateColumns.split(" ").length,
      );
      const index = all.indexOf(card);
      const row_end = Math.min(all.length - 1, Math.floor(index / per_row) * per_row + per_row - 1);
      const last = all[row_end];
      if (last && row_end >= index) last.after(detail);
      else grid.append(detail);
    }
  }
}

// The four families a reader thinks in, read off the name rather than kept in
// a second table that could drift from the first.
function group_of(row) {
  if (!row.quantized) return "float";
  if (row.name.startsWith("IQ")) return "i";
  if (row.name.endsWith("_K")) return "k";
  if (/^Q\d+_[01]$/.test(row.name)) return "block";
  return "packed";
}
