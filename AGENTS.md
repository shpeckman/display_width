# AGENTS.md

display_width is a Crystal shard for the terminal cells (0, 1 or 2) that
code points, UTF-8 bytes and text take: Unicode 18.0.0 tables embedded at
compile time, UAX #29 grapheme clusters, kitty's algorithm for splitting
text into cells, escape sequences that take no cells, a stream for text
arriving in chunks, and truncate/pad/column helpers. Nothing allocates.
Namespace `DisplayWidth`. No dependencies; Crystal >= 1.21.

## Layout

```tree
.
├─╴src/
│  ├─╴display_width.cr      entry; `DisplayWidth.of` and `DisplayWidth.each_cluster`.
│  ╰─╴display_width/
│     ├─╴codepoint.cr       `Codepoint` alias (`Char | Int32 | UInt32`), `ord`.
│     ├─╴engine.cr          `Engine`, clusters over `Placer` and `Escape`, shared by the API.
│     ├─╴escape.cr          `Escape`, escape sequences as kitty's parser reads them.
│     ├─╴layout.cr          `Align`, `fit`, `truncate`, `pad`, `offset_at`, `column`.
│     ├─╴placer.cr          `Placer`, kitty's placement of code points in cells (`Step`).
│     ├─╴policy.cr          `Policy` (*ambiguous*, *graphemes*, *escapes*), `Policy#cells`.
│     ├─╴props.cr           `Props` (packed per-code-point bits) and the `Break`, `Conjunct`, `Cells` enums.
│     ├─╴segmenter.cr       `Segmenter`, UAX #29 boundaries one code point at a time.
│     ├─╴stream.cr          `Stream`, `write`/`advance`/`flush` for chunked input.
│     ├─╴tables.cr          embeds `src/display_width/data/tables.bin` at compile time, `UNICODE_VERSION`, `DisplayWidth.props`.
│     ├─╴utf8.cr            `UTF8`, decoding with U+FFFD per maximal subpart and the ASCII fast path.
│     ╰─╴data/tables.bin    generated tables (header line, distinct props, stage 1, stage 2).
├─╴tools/gen_tables.cr      regenerates `src/display_width/data/tables.bin` and `spec/data`.
├─╴spec/                    specs per module; `conformance_spec.cr` reads `spec/data`.
╰─╴bench/                   `all.cr` runs `width.cr` with `bench_helper.cr`.
```

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
  `src/display_width/data/tables.bin` and `spec/data` (`GraphemeBreakTest.txt`,
  `emoji-qualified.txt`, `emoji-variation-sequences.txt`); run
  `make spec` after it. `src/display_width/tables.cr` checks the header at
  compile time and raises "run make tables" on a bad or truncated file.
  Don't edit `src/display_width/data/tables.bin` or `spec/data` by hand.
- One Crystal compile at a time; never run builds, specs, benches or docs
  in parallel.
- Docs: the repo tracks no `docs/` (git-ignored); generate into a
  temporary directory and delete it afterwards. Public docs list
  `DisplayWidth`, `Align`, `Codepoint`, `Placer`, `Placer::Step`,
  `Policy`, `Props` and `Stream`.
- Format only the files you touched: `dev crystal tool format <files>`.

## `:nodoc:` inventory

Public but internal, in 2 files:

- `props.cr`: `Break`, `Conjunct`, `Cells`, `Props.pack`; used by
  `tools/gen_tables.cr`.
- `segmenter.cr`: `Segmenter` (`new`, `step`); used by
  `spec/conformance_spec.cr`.

Everything else internal is `private` or `protected`: `Engine`, `Escape`
and `UTF8` are private types, the table constants in `tables.cr` are
private, and `DisplayWidth.ord`, `Placer#open?` and the `Props` readers
`#gcb`, `#incb`, `#emoji_base?`, `#cells`, `#widens?` are protected.

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
- The public API must be ergonomic.
- Avoid shotgun surgery: one change, one place.
- Deliver complete files: no stubs or placeholders, everything discussed
  fully implemented; don't add functionality nobody asked for.
- Never change the version in shard.yml.
- Every file starts with a comment holding its path (`# src/display_width.cr`).

### Visibility

Expose only what users need; the compiler enforces the rest.

- `private` for types, constants and methods used only inside their own
  type or namespace.
- `protected` for methods that other types in the same namespace call.
- `# :nodoc:` as the first line of the doc comment for public code that
  other shards or the specs must reach but users should not use. Internal
  notes may follow the directive.
- Everything else is the public API: documented, ergonomic and kept stable.
- Check with `crystal docs`: the generated API must show only the intended
  public surface.

### Doc comments

- The first sentence says what the feature does or returns, in third
  person present ("Returns …").
- Add a paragraph only for contracts the caller cannot infer (lifetime,
  ownership, required flags, what raises) or for a short example in a code
  block.
- No implementation details, algorithms, byte layouts or tuning notes;
  those go in a plain comment after `:nodoc:` or in this file.
- No comments on self-explanatory getters and predicates.
- Italicize parameters (`*name*`); reference features in backticks
  (`` `#method` ``, `` `.new` ``, `` `Type` ``) so they link; `:ditto:` for
  overloads.
- Never reference private or `:nodoc:` features from public doc comments.

### Documentation

Keep both files in sync with the code:

- `README.md`: usage and the documented public API only, plus user-visible
  details too long for doc comments.
- `AGENTS.md`: repository layout, commands, these standards and everything
  `:nodoc:`.

### Releases

- Work on `dev` or a feature branch, never `main`.
- Ship only when the user asks.
- Prefix shell commands that change files with `dev`; it bounds their
  output and records the changed files in a journal with undo.

## Modes

- Analysis Mode is the default at conversation start; `/dev:analyze`
  switches to it, `/dev:code` to Code Mode. A mode stays active until the
  other command is used.
- Begin every message with `ANALYSIS MODE` or `CODE MODE`.
- Analysis Mode: write no code, except small snippets that clarify a
  point. When the user provides code at the start of a conversation,
  describe what it does; don't scrutinize or critique it.
- Code Mode: the code standards above apply, also to snippets shown in
  Analysis Mode.

## Behavior

- Follow explicit user scope for files, directories and repositories;
  the current directory is only the fallback when no scope is stated.
- Always write in English, whatever language the user writes in.
- Take responsibility for mistakes: own and correct them.
- Search online before making factual claims, when online search is
  available.
- Respond like a smart caveman, also when thinking: no articles, filler,
  pleasantries or hedging; fragments are fine.
- Technical terms stay exact; code blocks stay unchanged.
- Pattern: [thing] [action] [reason]. [next step].
