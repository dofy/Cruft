#!/usr/bin/env bash
#
# Localization gate.
#
# Catches the four ways a String Catalog drifts:
#   1. a key used from source that has no entry in the catalog — missing keys
#      fall back to the English defaultValue, so nothing looks broken in an
#      English build and the gap goes unnoticed;
#   2. an entry missing a zh-Hans or zh-Hant translation, or still marked
#      new / needs_review / stale;
#   3. an entry no source key references any more;
#   4. Chinese copy hardcoded in Swift instead of going through the catalog.
#
# Rule 4 has legitimate exceptions (persisted identifiers, parser fixtures,
# sample data). Mark those lines with a trailing `// i18n-exempt` comment.
#
# Usage: scripts/check-localization.sh
set -uo pipefail
cd "$(dirname "$0")/.."

exec python3 - "$@" <<'PYTHON'
import json
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path.cwd()

# (catalog, source roots) pairs.
UNITS = [
    (ROOT / "Sources/Localizable.xcstrings", [ROOT / "Sources"]),
]
INFO_PLIST_CATALOG = ROOT / "Sources/InfoPlist.xcstrings"
REQUIRED = ("en", "zh-Hans", "zh-Hant")
GOOD_STATE = "translated"
CJK = re.compile(r"[㐀-䶿一-鿿豈-﫿　-〿＀-￯]")
CALL = re.compile(r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"')

failures = []


def swift_files(roots):
    for root in roots:
        for path in sorted(root.glob("**/*.swift")):
            yield path


def literal_end(src, i):
    """Index just past the Swift string literal starting at src[i] == '"'."""
    if src.startswith('"""', i):
        return src.index('"""', i + 3) + 3
    j = i + 1
    while j < len(src):
        c = src[j]
        if c == "\\":
            if src[j + 1] == "(":
                k, depth = j + 2, 1
                while depth > 0:
                    if src[k] == "(":
                        depth += 1
                    elif src[k] == ")":
                        depth -= 1
                    elif src[k] == '"':
                        k = literal_end(src, k)
                        continue
                    k += 1
                j = k
                continue
            j += 2
            continue
        if c == '"':
            return j + 1
        j += 1
    return len(src)


def literals(src):
    """(start, end, text) for every top-level string literal, comments skipped."""
    i = 0
    while i < len(src):
        c = src[i]
        if src.startswith("//", i):
            i = src.find("\n", i)
            if i == -1:
                return
            continue
        if src.startswith("/*", i):
            end = src.find("*/", i + 2)
            i = len(src) if end == -1 else end + 2
            continue
        if c == '"':
            end = literal_end(src, i)
            yield i, end, src[i:end]
            i = end
            continue
        i += 1


def used_keys(roots):
    keys = {}
    for path in swift_files(roots):
        if "Tests" in path.parts:
            continue
        src = path.read_text()
        for m in CALL.finditer(src):
            keys.setdefault(m.group(1), []).append(
                f"{path.relative_to(ROOT)}:{src[:m.start()].count(chr(10)) + 1}"
            )
    return keys


def catalog_keys(path):
    if not path.exists():
        failures.append(f"{path.relative_to(ROOT)}: catalog not found")
        return {}, None
    data = json.loads(path.read_text())
    if data.get("sourceLanguage") != "en":
        failures.append(
            f"{path.relative_to(ROOT)}: sourceLanguage is "
            f"{data.get('sourceLanguage')!r}, expected 'en'"
        )
    return data.get("strings", {}), data


def string_units(node):
    """Every stringUnit under a localization, descending through variations."""
    if not isinstance(node, dict):
        return
    if "stringUnit" in node:
        yield node["stringUnit"]
    for child in node.get("variations", {}).values():
        for case in child.values():
            yield from string_units(case)


def check_translations(path, strings):
    for key, entry in sorted(strings.items()):
        locs = entry.get("localizations", {})
        for lang in REQUIRED:
            units = list(string_units(locs.get(lang, {})))
            if not units or not all(u.get("value") for u in units):
                failures.append(f"{path.relative_to(ROOT)}: {key} has no {lang} value")
                continue
            for unit in units:
                if unit.get("state", GOOD_STATE) != GOOD_STATE:
                    failures.append(
                        f"{path.relative_to(ROOT)}: {key} [{lang}] state is "
                        f"{unit['state']!r}, expected 'translated'"
                    )
        if entry.get("extractionState") == "stale":
            failures.append(f"{path.relative_to(ROOT)}: {key} is marked stale")


def check_hardcoded(roots):
    for path in swift_files(roots):
        if "Tests" in path.parts:
            continue
        src = path.read_text()
        lines = src.split("\n")
        # Spans covered by a defaultValue: literal are allowed to be anything;
        # everything else must not carry Chinese copy.
        allowed = set()
        for m in re.finditer(r"defaultValue:\s*", src):
            i = m.end()
            while i < len(src) and src[i] in " \n\t":
                i += 1
            if i < len(src) and src[i] == '"':
                allowed.add(i)
        for start, _end, text in literals(src):
            if start in allowed or not CJK.search(text):
                continue
            line_no = src[:start].count("\n") + 1
            if "i18n-exempt" in lines[line_no - 1]:
                continue
            failures.append(
                f"{path.relative_to(ROOT)}:{line_no}: Chinese in a plain string "
                f"literal — route it through String(localized:) or mark the line "
                f"// i18n-exempt: {text[:48]}"
            )


for catalog, roots in UNITS:
    strings, _ = catalog_keys(catalog)
    if not strings:
        continue
    used = used_keys(roots)
    for key, sites in sorted(used.items()):
        if key not in strings:
            failures.append(
                f"{catalog.relative_to(ROOT)}: missing key {key!r} (used at {sites[0]})"
            )
    for key in sorted(set(strings) - set(used)):
        failures.append(f"{catalog.relative_to(ROOT)}: orphan key {key!r}")
    check_translations(catalog, strings)
    check_hardcoded(roots)

info_strings, _ = catalog_keys(INFO_PLIST_CATALOG)
check_translations(INFO_PLIST_CATALOG, info_strings)

with tempfile.TemporaryDirectory() as tmp:
    for catalog, _ in UNITS + [(INFO_PLIST_CATALOG, None)]:
        if not catalog.exists():
            continue
        out = pathlib.Path(tmp) / catalog.parent.name
        out.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            ["xcrun", "xcstringstool", "compile", str(catalog), "-o", str(out)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip().splitlines()
            failures.append(
                f"{catalog.relative_to(ROOT)}: xcstringstool compile failed: "
                f"{detail[0] if detail else result.returncode}"
            )

if failures:
    print(f"localization check FAILED ({len(failures)} problems)")
    for f in failures:
        print("  " + f)
    sys.exit(1)
print("localization check passed")
PYTHON
