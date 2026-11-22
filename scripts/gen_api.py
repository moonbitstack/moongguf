"""Write docs/api.html from the interface file and the `///` comments in the
sources, so that the reference follows the code.

    python scripts/gen_api.py

Every public name the interface declares has to appear on the page; a name the
script cannot place is a build failure rather than a gap nobody notices.
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGE = "moonbitstack/moongguf"
FOLDER = "src"
INTRO = (
    "One package. Files, metadata tables, tensor indexes and the bytes behind "
    "them, with a refusal for everything that is not a GGUF file."
)
SECTIONS = ["Values", "Errors", "Types and methods"]

DECL = re.compile(
    r"^pub(?:\((?:all|open)\))?\s+(fn(?:\[[^\]]*\])?|let|struct|enum|suberror|trait|type)\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)"
)
TRAIT_METHOD = re.compile(
    r"::(equal|not_equal|output|to_string|to_repr|hash|hash_combine|compare)\("
)
FENCE = re.compile(r"```[^\n`]*\n(.*?)```", re.S)


def sources():
    for path in sorted((ROOT / FOLDER).glob("*.mbt")):
        if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        yield path.read_text(encoding="utf-8").splitlines()


def docs_of() -> dict[str, str]:
    """Doc comments by name, and `Type.variant` for a note written beside one."""
    out: dict[str, str] = {}
    for lines in sources():
        pending: list[str] = []
        owner = None
        for line in lines:
            stripped = line.strip()
            if stripped == "///|":
                pending = []
                continue
            if stripped.startswith("///"):
                pending.append(stripped[3:].strip())
                continue
            if stripped.startswith("#"):
                continue
            found = DECL.match(line)
            if found:
                if pending:
                    out[found.group(2)] = "\n".join(pending)
                owner = (
                    found.group(2)
                    if found.group(1) in ("enum", "suberror", "struct")
                    and line.rstrip().endswith("{")
                    else None
                )
                pending = []
                continue
            if owner:
                if line.startswith("}"):
                    owner = None
                else:
                    variant = re.match(r"\s+([A-Z]\w*)\s*(?://\s*(.+))?$", line)
                    if variant and variant.group(2):
                        out[f"{owner}.{variant.group(1)}"] = variant.group(2).strip()
            pending = []
    return out


def items_of() -> list[dict]:
    """The interface file, in the order it lists things, with its own headings."""
    lines = (ROOT / FOLDER / "pkg.generated.mbti").read_text(encoding="utf-8").splitlines()
    items: list[dict] = []
    block = None
    section = SECTIONS[0]
    derives: list[str] = []
    for line in lines:
        heading = re.match(r"^//\s+(.+)$", line)
        if heading:
            name = heading.group(1).strip()
            if name in SECTIONS:
                section = name
            continue
        derived = re.match(r"^#derive\((.*)\)$", line)
        if derived:
            derives = [part.strip().split(".")[-1] for part in derived.group(1).split(",")]
            continue
        if block is not None:
            if line.startswith("}"):
                items.append(block)
                block = None
            else:
                block["variants"].append(line.strip())
            continue
        found = re.match(r"pub(?:\((?:all|open)\))?\s+(enum|struct|suberror)\s+(\w+)", line)
        if found:
            block = {
                "kind": found.group(1),
                "name": found.group(2),
                "sig": line.rstrip(" {"),
                "variants": [],
                "derives": derives,
                "section": section,
            }
            derives = []
            if not line.rstrip().endswith("{"):
                items.append(block)
                block = None
            continue
        found = re.match(r"pub fn (\w+)::(\w+)", line)
        if found:
            items.append(
                {
                    "kind": "method",
                    "name": f"{found.group(1)}::{found.group(2)}",
                    "owner": found.group(1),
                    "sig": line,
                    "section": section,
                }
            )
            continue
        found = re.match(r"pub fn (\w+)", line)
        if found:
            items.append(
                {"kind": "fn", "name": found.group(1), "sig": line, "section": section}
            )
            continue
        found = re.match(r"pub impl (\w+) for (\w+)", line)
        if found:
            items.append(
                {
                    "kind": "impl",
                    "name": found.group(1),
                    "owner": found.group(2),
                    "sig": line,
                    "section": section,
                }
            )
            continue
        found = re.match(r"pub let (\w+)", line)
        if found:
            items.append(
                {"kind": "let", "name": found.group(1), "sig": line, "section": section}
            )
    return items


def inline(text: str) -> str:
    if not text:
        return ""
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return f"<p>{escaped}</p>"


def prose(text: str) -> str:
    """A doc comment: prose as paragraphs, a fenced block as a code block."""
    if not text:
        return ""
    out, at = [], 0
    for found in FENCE.finditer(text):
        out.append(inline(text[at : found.start()].strip()))
        code = html.escape(found.group(1).strip("\n"), quote=False)
        out.append(f'<pre class="sig">{code}</pre>')
        at = found.end()
    out.append(inline(text[at:].strip()))
    return "".join(part for part in out if part)


def sig(text: str) -> str:
    return f'<pre class="sig">{html.escape(text.strip(), quote=False)}</pre>'


def anchor(name: str) -> str:
    return name.replace("::", "-").lower()


def declared() -> tuple[set[str], set[str]]:
    """Every name the interface declares, and every type it says it implements
    a trait for, so that nothing can be left off the page."""
    names, impls = set(), set()
    for line in (ROOT / FOLDER / "pkg.generated.mbti").read_text(encoding="utf-8").splitlines():
        found = re.match(
            r"pub(?:\((?:all|open)\))?\s+(?:fn|let|struct|enum|suberror|trait|type|typealias)\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)",
            line,
        )
        if found:
            names.add(found.group(1))
        found = re.match(r"pub impl \w+ for (\w+)", line)
        if found:
            impls.add(found.group(1))
    return names, impls


def render() -> None:
    docs = docs_of()
    items = items_of()
    names, impls = declared()

    types = [i for i in items if i["kind"] in ("enum", "struct", "suberror")]
    fns = [i for i in items if i["kind"] == "fn"]
    values = [i for i in items if i["kind"] == "let"]
    methods: dict[str, list[dict]] = {}
    traits: dict[str, list[str]] = {}
    for item in items:
        if item["kind"] == "method" and not TRAIT_METHOD.search(item["sig"]):
            methods.setdefault(item["owner"], []).append(item)
        if item["kind"] == "impl":
            traits.setdefault(item["owner"], []).append(item["name"])

    nav, body = [], []
    for section in SECTIONS:
        group = [i for i in items if i["section"] == section]
        if not group:
            continue
        nav.append(f'<li><span class="group">{html.escape(section)}</span></li>')

        if section == "Values":
            for item in values + fns:
                nav.append(
                    f'<li><a href="#{anchor(item["name"])}">{html.escape(item["name"])}</a></li>'
                )
            for item in values + fns:
                body.append('<article class="api-entry" data-track')
                body.append(f' id="{anchor(item["name"])}" data-name="{item["name"].lower()}">')
                body.append(
                    f'<h3><span class="kind">{item["kind"]}</span>{html.escape(item["name"])}</h3>'
                )
                body.append(sig(item["sig"]) + prose(docs.get(item["name"], "")) + "</article>")

        if section == "Errors":
            errors = [i for i in types if i["kind"] == "suberror"]
            for item in errors:
                nav.append(
                    f'<li><a href="#{anchor(item["name"])}">{html.escape(item["name"])}</a></li>'
                )
            for item in errors:
                body.append(
                    f'<article class="api-entry" data-track id="{anchor(item["name"])}" data-name="{item["name"].lower()}">'
                )
                body.append(
                    f'<h3><span class="kind">suberror</span>{html.escape(item["name"])}</h3>'
                )
                body.append(sig(item["sig"]) + prose(docs.get(item["name"], "")))
                body.append('<ul class="variants">')
                for variant in item["variants"]:
                    name = variant.split("(")[0]
                    note = docs.get(f'{item["name"]}.{name}', "")
                    body.append(
                        f"<li><code>{html.escape(variant.rstrip(','))}</code>"
                        + (f"<small>{html.escape(note)}</small>" if note else "")
                        + "</li>"
                    )
                body.append("</ul>")
                for trait in traits.get(item["name"], []):
                    body.append(prose(f"The error is a `{trait}`: its text is what a caller prints."))
                body.append("</article>")

        if section == "Types and methods":
            plain = [i for i in types if i["kind"] != "suberror"]
            for item in plain:
                nav.append(
                    f'<li><a href="#{anchor(item["name"])}">{html.escape(item["name"])}</a></li>'
                )
            for item in plain:
                body.append(
                    f'<article class="api-entry" data-track id="{anchor(item["name"])}" data-name="{item["name"].lower()}">'
                )
                body.append(
                    f'<h3><span class="kind">{item["kind"]}</span>{html.escape(item["name"])}</h3>'
                )
                body.append(prose(docs.get(item["name"], "")))
                body.append(sig(item["sig"] + (" {" if item["variants"] else "")))
                if item["variants"]:
                    body.append('<ul class="variants">')
                    for variant in item["variants"]:
                        name = variant.split("(")[0]
                        note = docs.get(f'{item["name"]}.{name}', "")
                        body.append(
                            f"<li><code>{html.escape(variant.rstrip(','))}</code>"
                            + (f"<small>{html.escape(note)}</small>" if note else "")
                            + "</li>"
                        )
                    body.append("</ul>")
                said = []
                if traits.get(item["name"]):
                    said.append(
                        "implements " + ", ".join(f"`{t}`" for t in traits[item["name"]])
                    )
                if item.get("derives"):
                    said.append("derives " + ", ".join(f"`{d}`" for d in item["derives"]))
                if said:
                    body.append(prose("The type " + ", and ".join(said) + "."))
                for method in methods.get(item["name"], []):
                    body.append(
                        f'<div class="member" id="{anchor(method["name"])}" data-name="{method["name"].lower()}">'
                    )
                    body.append(sig(method["sig"]))
                    body.append(prose(docs.get(method["name"], "")))
                    body.append("</div>")
                body.append("</article>")

    shown = {i["name"] for i in fns + values + types}
    shown |= {m["name"] for group in methods.values() for m in group}
    missing = sorted(
        name
        for name in names
        if name not in shown and name.split("::")[0] not in {t["name"] for t in types}
    )
    if missing:
        raise SystemExit(f"the reference leaves out {', '.join(missing)}")
    absent = sorted(name for name in impls if name not in {t["name"] for t in types})
    if absent:
        raise SystemExit(f"the reference leaves out the traits of {', '.join(absent)}")

    page = (ROOT / "docs" / "api.template.html").read_text(encoding="utf-8")
    page = page.replace("<!-- intro -->", prose(INTRO))
    page = page.replace("<!-- nav -->", "\n".join(nav))
    page = page.replace("<!-- body -->", "\n".join(body))
    page = page.replace("<!-- count -->", str(len(names)))
    (ROOT / "docs" / "api.html").write_text(page, encoding="utf-8", newline="\n")
    print(f"{len(names)} public names on the page")


if __name__ == "__main__":
    render()
    sys.exit(0)
