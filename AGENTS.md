# AGENTS.md

display_width is a Crystal shard for the terminal cells (0, 1 or 2) that
code points, UTF-8 bytes and text take: Unicode 18.0.0 tables embedded at
compile time, UAX #29 grapheme clusters, kitty's algorithm for splitting
text into cells, escape sequences that take no cells, a stream for text
arriving in chunks, and truncate/pad/column helpers. Nothing allocates.
Namespace `DisplayWidth`. No dependencies; Crystal >= 1.21.

## Layout

- `src/display_width.cr`: entry; `DisplayWidth.of` and `DisplayWidth.each_cluster`.
- `src/display_width/codepoint.cr`: `Codepoint` alias (`Char | Int32 | UInt32`), `ord`.
- `src/display_width/props.cr`: `Props` (packed per-code-point bits) and the `Break`, `Conjunct`, `Cells` enums.
- `src/display_width/tables.cr`: embeds `data/tables.bin` at compile time, `UNICODE_VERSION`, `DisplayWidth.props`.
- `src/display_width/policy.cr`: `Policy` (*ambiguous*, *graphemes*, *escapes*), `Policy#cells`.
- `src/display_width/segmenter.cr`: `Segmenter`, UAX #29 boundaries one code point at a time.
- `src/display_width/placer.cr`: `Placer`, kitty's placement of code points in cells (`Step`).
- `src/display_width/escape.cr`: `Escape`, escape sequences as kitty's parser reads them.
- `src/display_width/utf8.cr`: `UTF8`, decoding with U+FFFD per maximal subpart and the ASCII fast path.
- `src/display_width/engine.cr`: `Engine`, clusters over `Placer` and `Escape`, shared by the API.
- `src/display_width/stream.cr`: `Stream`, `write`/`advance`/`flush` for chunked input.
- `src/display_width/layout.cr`: `Align`, `fit`, `truncate`, `pad`, `offset_at`, `column`.
- `data/tables.bin`: generated tables (header line, distinct props, stage 1, stage 2).
- `tools/gen_tables.cr`: regenerates `data/tables.bin` and `spec/data`.
- `bench/`: `all.cr` runs `width.cr` with `bench_helper.cr`.
- `spec/`: specs per module; `conformance_spec.cr` reads `spec/data`.

## Commands

```
make                     make help: lists the targets
make spec                crystal spec --threads $(THREADS)
make bench               crystal build --release --no-debug bench/all.cr, runs it, removes bench-suite
make tables              crystal run tools/gen_tables.cr (from unicode.org)
make tables UCD=dir      the same from a local mirror of Public/<version>/
crystal docs src/display_width.cr -o /tmp/<dir>
```
`THREADS` defaults to 2, `CRYSTAL` to `crystal`.

- Tables: the Unicode version is `UNICODE_VERSION` in
  `tools/gen_tables.cr` (sources from
  `https://www.unicode.org/Public/<version>`). `make tables` rewrites
  `data/tables.bin` and `spec/data` (`GraphemeBreakTest.txt`,
  `emoji-qualified.txt`, `emoji-variation-sequences.txt`); run
  `make spec` after it. `src/display_width/tables.cr` checks the header at
  compile time and raises "run make tables" on a bad or truncated file.
  Don't edit `data/tables.bin` or `spec/data` by hand.
- One Crystal compile at a time; never run builds, specs, benches or docs
  in parallel.
- Docs: the repo tracks no `docs/` (git-ignored); generate into a
  temporary directory and delete it afterwards. Public docs list
  `DisplayWidth`, `Align`, `Codepoint`, `Placer`, `Placer::Step`,
  `Policy`, `Props` and `Stream`.
- Format only the files you touched: `dev crystal tool format <files>`.

`:nodoc:` inventory (8 files):

- `codepoint.cr`: `DisplayWidth.ord`.
- `engine.cr`: `Engine`.
- `escape.cr`: `Escape`.
- `placer.cr`: `Placer#open?`.
- `props.cr`: `Break`, `Conjunct`, `Cells`; `Props.pack`, `#gcb`, `#incb`,
  `#emoji_base?`, `#cells`, `#widens?`.
- `segmenter.cr`: `Segmenter`.
- `tables.cr`: `SHIFT`, `MASK`, `STAGE1_WIDE`, `TABLES`, `PROPS_AT`,
  `STAGE1_AT`, `STAGE2_AT`.
- `utf8.cr`: `UTF8`.

Users: asekii and asekii-app use only public API, none of the `:nodoc:`
items. asekii (`src/asekii/terminal.cr`, `terminal/parser.cr`,
`terminal/text_sizing.cr`, `tty/screen.cr`): `Policy`, `Placer`
(`put`, `reset`, `width`, `policy`, `plain?`, `plain!`),
`DisplayWidth.props`, `Props#plain?`, `Policy#cells`, `DisplayWidth.of`,
`DisplayWidth.each_cluster`. asekii-app (`src/app/render/row_builder.cr`):
`Policy`, `DisplayWidth.props`, `Props#pictographic?`, `Policy#cells`,
`DisplayWidth.each_cluster`. Changing public signatures breaks them.

## Code standards

- Compiler-friendly, performance-focused, idiomatic Crystal.
- Data-driven design: tables and records over branching logic.
- Every file starts with a comment holding its path (`# src/display_width.cr`).
- The public API must be ergonomic.
- Avoid shotgun surgery: one change, one place.
- No stubs or placeholders; don't add functionality nobody asked for.
- Never change the version in shard.yml.
- Visibility: `private` for internal code, `protected` for callers in the
  same namespace, `# :nodoc:` as the first doc line for public but internal
  code. Check with `crystal docs`.
- Doc comments: third person present, *param* in italics, backtick
  references, `:ditto:`; no implementation details; public docs never
  reference private or `:nodoc:` items.
- Keep README.md and AGENTS.md in sync with the code.
- Work on `dev`, never `main`.
- Prefix shell commands that change files with `dev`.
