// The theme: the first visit follows the system, and a reader who picks one
// keeps it for the rest of the visit. A plain script in the head, so the choice
// is on the root element before the first paint.
const root = document.documentElement;
root.classList.add("js");
const KEY = "moongguf-theme";
try {
  // A reload is a fresh look at the page, so it follows the system again; a
  // step from one page to another during the same visit keeps the choice.
  const navigation = performance.getEntriesByType?.("navigation")[0];
  if (navigation?.type === "reload") sessionStorage.removeItem(KEY);
  const saved = sessionStorage.getItem(KEY);
  if (saved === "dark" || saved === "light") root.dataset.theme = saved;
} catch {
  /* a browser that refuses storage still gets the system theme */
}

function current() {
  const chosen = root.dataset.theme;
  if (chosen === "dark" || chosen === "light") return chosen;
  return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function wire() {
  const button = document.querySelector(".theme-toggle");
  if (!button) return;
  const relabel = () => {
    const next = current() === "dark" ? "light" : "dark";
    const text = `Switch to the ${next} theme`;
    button.setAttribute("aria-label", text);
    button.setAttribute("title", text);
  };
  relabel();
  button.addEventListener("click", () => {
    const next = current() === "dark" ? "light" : "dark";
    root.dataset.theme = next;
    try {
      sessionStorage.setItem(KEY, next);
    } catch {
      /* the choice lasts the page, which is what a reader sees anyway */
    }
    relabel();
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", wire, { once: true });
} else {
  wire();
}
