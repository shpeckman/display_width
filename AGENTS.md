# AGENTS.md

Orientation for AI agents working on this repository.

## What this is

`display_width` is a Crystal shard that says how many terminal cells code points and text take (0, 1 or 2 per cluster). It uses Unicode 18.0.0 data, segments by UAX #29 revision 49, and places clusters in cells by kitty's algorithm for splitting text into cells (the kitty text sizing protocol docs; kitty's `gen/wcwidth.py` and `kitty/screen.c` are the reference where the docs are silent). Input is code points (`Char`, `Int32`, `UInt32`) or UTF-8 (`String`, `Bytes`), whole or streamed. It has no dependencies beyond the standard library, and must stay that way.

## Layout

- `src/display_width.cr` — the public entry points: `DisplayWidth.of` (code point, `String`, `Bytes`, code point sequences) and `DisplayWidth.each_cluster`.
- `src/display_width/codepoint.cr` — the `Codepoint` alias and `ord`, which maps every code point type to an `Int32` (invalid values to -1).
- `src/display_width/props.cr` — the `Break`, `Conjunct` and `Cells` enums and `Props`, the packed per-code-point properties. The bit layout lives here only; the generator requires this file to pack the table.
- `src/display_width/tables.cr` — embeds `data/tables.bin` with `read_file`, checks its header and defines `UNICODE_VERSION` and `DisplayWidth.props`, the two-stage lookup.
- `src/display_width/segmenter.cr` — `Segmenter`: UAX #29 boundaries one code point at a time, with a one-byte state. `joins` holds the pair rules (GB3 to GB9b); `step` adds the stateful ones (GB9c, GB11, GB12/13).
- `src/display_width/utf8.cr` — `UTF8.decode` (maximal-subpart replacement, a negative size for a well-formed start cut off by the end of input) and `UTF8.ascii`, the eight-bytes-at-a-time printable ASCII scan.
- `src/display_width/policy.cr` — `Policy` (`ambiguous`, `graphemes?`) and `cells`, which maps a width class to cells.
- `src/display_width/engine.cr` — `Engine`: kitty's cell placement over one open cluster. `put` feeds a code point, `feed` feeds UTF-8 (with the ASCII run path), `finish` closes the open cluster. Every public entry point goes through it.
- `src/display_width/stream.cr` — `Stream`: an `Engine` plus a carry of up to four bytes for UTF-8 split across chunks; `write`, `advance`, `flush`.
- `tools/gen_tables.cr` — downloads (or reads a mirror of) the UCD files and writes `data/tables.bin` and `spec/data/`.
- `data/tables.bin` — generated; never edit by hand.
- `spec/` — `codepoint_spec.cr`, `text_spec.cr` (clusters and kitty's placement rules), `utf8_spec.cr`, `stream_spec.cr`, `policy_spec.cr`, `conformance_spec.cr` (GraphemeBreakTest.txt, every fully-qualified emoji, emoji-variation-sequences.txt). `spec/data/` is generated with the tables.
- `bench/` — `bench_helper.cr`, `width.cr` (lines of ASCII, Latin, CJK, emoji and combining text), `all.cr`.

## Commands

- `make spec` (`crystal spec --threads 2`) — run the suite.
- `crystal spec spec/text_spec.cr --threads 2` — run one file.
- `make bench` — release build of `bench/all.cr`, run, removed.
- `make tables` — regenerate `data/tables.bin` and `spec/data/` from unicode.org; `make tables UCD=dir` reads a local mirror of `Public/<version>/`.
- `crystal build --no-codegen src/display_width.cr` — fast compile check.
- Run one compile at a time, with `--threads 2`: parallel compiles have exhausted memory on this machine.

## Rules

- Cell widths follow kitty, not wcwidth: in decreasing priority, regional indicators, East Asian W/F plus the CJK ideograph ranges, and kitty's wide emoji take 2; kitty's marks (`M*`, `Cf`, `Other_Default_Ignorable_Code_Point`, and the skin tones and U+0000, which earlier rules or the C0 check already decide) take 0; East Asian Ambiguous takes `Policy#ambiguous`; everything else takes 1. Change the width rules in `tools/gen_tables.cr` only, then run `make tables`.
- Placement follows `kitty/screen.c`, not kitty's `wcswidth`: a zero-width code point with no cell to join takes no cells, and the next code point with a width starts a cell even if segmentation joins it. Keep that, and keep the specs that pin it.
- C0 controls are clusters of their own and reset the segmenter. DEL, C1, surrogates, noncharacters and values outside the code space are invalid: they join the open cluster (or start a zero-width one) and never step the segmenter.
- `each_cluster` covers the input without gaps, in order; `of` equals the sum of the widths `each_cluster` yields; `Stream#advance` sums to the same total. New behaviour keeps all three in step because all three go through `Engine`.
- The fast paths are exact, not approximations: `UTF8.ascii` only runs when the segmenter is `plain?`, `Props#plain?` short-cuts `Segmenter#step`, and `UTF8.decode`'s unrolled checks fall back to `subpart` for anything ill-formed. A change to the rules must keep them exact, and `conformance_spec.cr` must keep passing.
- The table format is defined once: `Props.pack` and the readers in `props.cr`, the header written by `gen_tables.cr` and checked by `tables.cr`. Change them together, and regenerate.
- Hot paths allocate nothing: no `String`, `Array` or closure per cluster. Blocks are yielded, not captured.
- Write combining marks, joiners, variation selectors and other invisible code points as `\u{XXXX}` escapes, never raw, so specs and examples can be read and reviewed. Use the braced form: some editing tools turn `\uXXXX` escapes into raw characters when they save a file. Run `crystal tool format --check src spec bench tools` before finishing.

## Code standards

- Compiler-friendly, performance-focused, idiomatic and data-driven.
- The user-facing API must be ergonomic.
- Prevent shotgun surgery: one change should land in one place.
- Every file starts with a comment containing its own path (e.g. `# src/display_width.cr`).
- Comments are sparse, but public API carries doc comments for `crystal docs`; internals are `:nodoc:`.
- Never edit the `version` field in `shard.yml`.
- Keep `README.md` (usage and public API) and this file in sync with the code.
