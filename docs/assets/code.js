// Colour for the code blocks. Only three things are picked out — comments,
// strings and numbers — so that the page never claims to understand the code
// better than a reader does. The text is walked, not re-parsed: what is in the
// block stays in the block, character for character.
const TOKEN =
  /(\/\/[^\n]*)|("(?:[^"\\\n]|\\.)*")|(\b\d[\d_]*(?:\.\d+)?(?:UL|L|U)?\b)|(@[a-z][\w]*)|(\b(?:let|fn|test|pub|for|in|if|else|match|raise|catch|with|mut|return|abort|struct|enum|impl|guard|defer|async)\b)/g;

const KIND = ["tok-com", "tok-str", "tok-num", "tok-key", "tok-key"];

for (const block of document.querySelectorAll("pre code")) {
  const text = block.textContent;
  if (!text.includes("(") && !text.includes("=")) continue;
  const fragment = document.createDocumentFragment();
  let at = 0;
  for (const found of text.matchAll(TOKEN)) {
    if (found.index > at) {
      fragment.append(text.slice(at, found.index));
    }
    const span = document.createElement("span");
    span.className = KIND[found.slice(1).findIndex((part) => part !== undefined)];
    span.textContent = found[0];
    fragment.append(span);
    at = found.index + found[0].length;
  }
  if (at < text.length) fragment.append(text.slice(at));
  block.replaceChildren(fragment);
}
