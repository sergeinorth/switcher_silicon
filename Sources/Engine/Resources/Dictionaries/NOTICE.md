# Dictionary sources

Bundled word lists used for layout awareness and conservative spell autocorrect.

## Russian full forms — `ru_words.txt.gz`

Used to decide “is the typed word already real?”.

- [danakt/russian-words](https://github.com/danakt/russian-words) — morphological word forms, MIT License
- [hingston/russian](https://github.com/hingston/russian) — frequency-ordered common words (University of Leeds corpus lists)

Words are lowercased Cyrillic-only tokens, length 2-32 (~1.5M forms).

## Russian frequency subset — `ru_freq.txt.gz`

Only these words are accepted as *spell corrections* (avoids rare morph junk).

- [hingston/russian](https://github.com/hingston/russian) — 10k / 50k / 100k Leeds corpus lists

~87k tokens.

## English — `en_words.txt.gz`

- [dwyl/english-words](https://github.com/dwyl/english-words) `words_alpha.txt` — Unlicense (public domain)

Words are lowercased ASCII letters only, length 2-32 (~370k).
