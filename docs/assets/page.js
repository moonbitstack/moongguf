// The page bar is hidden while the page stands at its top, the way a sheet
// shows no edge until it is lifted, and appears from the first scroll on. The
// lane keeps its width either way, so the page does not shift sideways.
const doc = document.documentElement;
const bar = document.querySelector(".topbar");

function mark() {
  doc.classList.toggle("at-top", scrollY === 0);
  if (bar) bar.classList.toggle("is-stuck", scrollY > 6);
}

addEventListener("scroll", mark, { passive: true });
mark();

// Sections rise into place once, a little after they are reached. Without
// script nothing is hidden, and with reduced motion the class is set at once.
const rise = [...document.querySelectorAll("[data-rise]")];
const still = matchMedia("(prefers-reduced-motion: reduce)");

if (rise.length && "IntersectionObserver" in window && !still.matches) {
  const seen = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add("is-in");
        seen.unobserve(entry.target);
      }
    },
    { rootMargin: "0px 0px -12% 0px", threshold: 0.04 },
  );
  for (const el of rise) seen.observe(el);
  // Whatever the observer misses — a page opened at an anchor, a very tall
  // section — is shown after a moment rather than staying invisible.
  setTimeout(() => rise.forEach((el) => el.classList.add("is-in")), 1400);
} else {
  for (const el of rise) el.classList.add("is-in");
}

// The guide and the reference both carry a list of where they are; the entry
// whose section is on screen is marked as the reader moves.
const tracked = [...document.querySelectorAll("[data-track]")];
if (tracked.length && "IntersectionObserver" in window) {
  const links = new Map(
    [...document.querySelectorAll(".toc a, .api-nav a")].map((a) => [
      a.getAttribute("href")?.slice(1),
      a,
    ]),
  );
  const near = new IntersectionObserver(
    (entries) => {
      // The last section to have started, not the first one still on screen:
      // a step stays on screen while the next one is already being read.
      const on = entries
        .filter((e) => e.isIntersecting)
        .sort((a, b) => b.target.offsetTop - a.target.offsetTop)[0];
      if (!on) return;
      for (const a of links.values()) a.classList.remove("is-current");
      links.get(on.target.id)?.classList.add("is-current");
    },
    { rootMargin: "-72px 0px -62% 0px", threshold: 0 },
  );
  for (const section of tracked) near.observe(section);
}

// The reference is long; a reader who knows the name of a function should be
// able to type it rather than scroll for it.
const search = document.querySelector("[data-filter]");
if (search) {
  const entries = [...document.querySelectorAll("[data-name]")];
  const links = [...document.querySelectorAll(".api-nav a")];
  const apply = () => {
    const needle = search.value.trim().toLowerCase();
    for (const entry of entries) {
      const hit = !needle || entry.dataset.name.includes(needle);
      entry.hidden = !hit;
    }
    for (const link of links) {
      const id = link.getAttribute("href")?.slice(1) ?? "";
      const entry = document.getElementById(id);
      link.parentElement.hidden = !!entry && entry.hidden;
    }
  };
  search.addEventListener("input", apply);
  search.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    search.value = "";
    apply();
  });
}
