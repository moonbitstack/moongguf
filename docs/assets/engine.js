// The library itself, compiled for the browser and loaded once per page. The
// build puts it in `engine/`; nothing in this file knows what a GGUF file is,
// it only carries the calls over.
let loading;

export function engine() {
  if (!loading) {
    const here = new URL(import.meta.url);
    const target = new URL("../engine/moongguf.js", here);
    // The page names this loader after the commit it was built from; the engine
    // it pulls in belongs to the same deploy, not to a cached earlier one.
    target.search = here.search;
    loading = import(target.href).catch((error) => {
      console.error("the engine did not load", error);
      return null;
    });
  }
  return loading;
}

// A refusal from the library arrives as JSON with `ok: false`, so a page can
// say what went wrong instead of emptying itself.
export function read(json) {
  try {
    return JSON.parse(json);
  } catch {
    return { ok: false, error: "the library returned something that is not JSON" };
  }
}

export function bytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) {
    const kb = n / 1024;
    return `${kb < 10 ? kb.toFixed(1) : Math.round(kb)} kB`;
  }
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

export const count = new Intl.NumberFormat("en", { useGrouping: true });

// A value as one short line: what a reader needs to recognise it, not the whole
// of a vocabulary.
export function value(input, type) {
  if (input === null || input === undefined) return "null";
  if (Array.isArray(input)) {
    if (type === "ARRAY" && Array.isArray(input[0])) {
      return `[${input.length} nested ${input.length === 1 ? "array" : "arrays"}]`;
    }
    const head = input.slice(0, 6).map((item) => value(item, "")).join(", ");
    return `[${head}${input.length > 6 ? `, … ${input.length} in all` : ""}]`;
  }
  if (typeof input === "string") {
    const short = input.length > 42 ? `${input.slice(0, 40)}…` : input;
    return `"${short}"`;
  }
  if (typeof input === "number") return String(input);
  return JSON.stringify(input);
}

// Bits per weight, which is the number a reader of a quantised file actually
// compares: bytes per block over values per block.
export function bits(encoding) {
  return (encoding.bytes * 8) / encoding.block;
}

export function bits_text(encoding) {
  const n = bits(encoding);
  return n < 10 ? n.toFixed(2) : n.toFixed(1);
}
