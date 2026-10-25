#!/bin/bash
# Rebuild bundled RU/EN word lists from upstream open sources.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/Sources/Engine/Resources/Dictionaries"
WORKDIR="/tmp/switcher_dicts"
mkdir -p "$OUT" "$WORKDIR"
cd "$WORKDIR"
export SWITCHER_DICT_OUT="$OUT"

echo "Downloading…"
curl -fsSL -o russian1251.txt "https://raw.githubusercontent.com/danakt/russian-words/master/russian.txt"
curl -fsSL -o words_alpha.txt "https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt"
curl -fsSL -o ru100k.txt "https://raw.githubusercontent.com/hingston/russian/master/100000-russian-words.txt"
curl -fsSL -o ru50k.txt "https://raw.githubusercontent.com/hingston/russian/master/50000-russian-words-cyrillic-only.txt"
curl -fsSL -o ru10k.txt "https://raw.githubusercontent.com/hingston/russian/master/10000-russian-words-cyrillic-only.txt"

python3 <<'PY'
import gzip, re, pathlib, os
root = pathlib.Path(os.environ["SWITCHER_DICT_OUT"])

ru_re = re.compile(r"^[а-яё]+$")
ru = set()
raw = open("russian1251.txt", "rb").read().decode("cp1251", errors="ignore")
for line in raw.splitlines():
    w = line.strip().lower()
    if 2 <= len(w) <= 32 and ru_re.match(w):
        ru.add(w)
for path in ["ru100k.txt", "ru50k.txt", "ru10k.txt"]:
    for line in open(path, encoding="utf-8", errors="ignore"):
        parts = line.strip().split()
        if not parts:
            continue
        cand = parts[0] if not parts[0].isdigit() else (parts[1] if len(parts) > 1 else "")
        w = cand.strip().lower()
        if 2 <= len(w) <= 32 and ru_re.match(w):
            ru.add(w)

en_re = re.compile(r"^[a-z]+$")
en = set()
for line in open("words_alpha.txt", encoding="utf-8", errors="ignore"):
    w = line.strip().lower()
    if 2 <= len(w) <= 32 and en_re.match(w):
        en.add(w)

freq = set()
for path in ["ru100k.txt", "ru50k.txt", "ru10k.txt"]:
    for line in open(path, encoding="utf-8", errors="ignore"):
        parts = line.strip().split()
        if not parts:
            continue
        cand = parts[0] if not parts[0].isdigit() else (parts[1] if len(parts) > 1 else "")
        w = cand.strip().lower()
        if 2 <= len(w) <= 32 and ru_re.match(w):
            freq.add(w)
for w in ["привет", "ошибок", "ошибка", "хорошо", "спасибо", "пожалуйста"]:
    freq.add(w)

with gzip.open(root / "ru_words.txt.gz", "wt", encoding="utf-8") as f:
    for w in sorted(ru):
        f.write(w + "\n")
with gzip.open(root / "ru_freq.txt.gz", "wt", encoding="utf-8") as f:
    for w in sorted(freq):
        f.write(w + "\n")
with gzip.open(root / "en_words.txt.gz", "wt", encoding="utf-8") as f:
    for w in sorted(en):
        f.write(w + "\n")
print(f"RU {len(ru)} -> {root/'ru_words.txt.gz'}")
print(f"FREQ {len(freq)} -> {root/'ru_freq.txt.gz'}")
print(f"EN {len(en)} -> {root/'en_words.txt.gz'}")
assert "привет" in ru and "ошибок" in ru and "hello" in en
assert "привет" in freq and "проревет" not in freq
PY

echo "Done."
