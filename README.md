# display_width

How many terminal cells a code point or a piece of text takes: 0, 1 or 2 per
cluster. It uses the Unicode 18.0.0 tables, segments text into grapheme
clusters (UAX #29 revision 49), and places them in cells by
[kitty's algorithm for splitting text into cells](https://sw.kovidgoyal.net/kitty/text-sizing-protocol/#the-algorithm-for-splitting-text-into-cells).
Escape sequences (styles, hyperlinks, ...) take no cells. Input can be code
points or UTF-8 bytes, whole or as a stream. On top of the widths, it
truncates, pads and expands tabs; below them, a terminal emulator can place
code points in cells one at a time.

It is built for TUIs: nothing allocates, printable ASCII is measured eight bytes
at a time, and the tables are embedded at compile time.

```crystal
require "display_width"

DisplayWidth.of('漢')                             # => 2
DisplayWidth.of("e\u{0301}")                     # => 1
DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB} ok") # => 5  👩‍💻 ok
DisplayWidth.of("\e[1mbold\e[0m")                # => 4

DisplayWidth.each_cluster("a\u{1F44D}\u{1F3FD}") do |offset, size, width|
  # {0, 1, 1}, then {1, 8, 2}
end

DisplayWidth.truncate("漢字漢字", 6) # => "漢字…"
DisplayWidth.pad("漢", 4)           # => "漢  "
```

## Contents

- [Installation](#installation)
- [Code points](#code-points)
- [Text](#text)
- [Clusters](#clusters)
- [Escape sequences](#escape-sequences)
- [Columns](#columns)
- [Policy](#policy)
- [Streams](#streams)
- [Placing code points](#placing-code-points)
- [How cells are counted](#how-cells-are-counted)
- [Performance](#performance)
- [Updating Unicode](#updating-unicode)

## Installation

Add the shard to `shard.yml` and run `shards install`:

```yaml
dependencies:
  display_width:
    github: shpeckman/display_width
```

Crystal 1.21 or newer is required. The shard has no dependencies.

## Code points

`DisplayWidth.of(codepoint)` gives the cells one code point takes on its own.
A code point is a `Char`, an `Int32` or a `UInt32` (`DisplayWidth::Codepoint`).

```crystal
DisplayWidth.of('a')        # => 1
DisplayWidth.of(0x1F600)    # => 2  😀
DisplayWidth.of('\u{0301}') # => 0  combining acute accent
DisplayWidth.of('\n')       # => 0
DisplayWidth.of(0xD800)     # => 0  surrogate
```

A code point's width says nothing about the clusters it joins: `'\u{263A}'`
(☺) takes 1 cell, `"\u{263A}\u{FE0F}"` takes 2. To measure a sequence of code
points, pass the sequence.

## Text

`DisplayWidth.of(text)` gives the sum of the widths of the clusters in `text`.
It takes a `String`, `Bytes`, or any `Enumerable` of `Char`, `Int32` or `UInt32`.

```crystal
DisplayWidth.of("Größe")                          # => 5
DisplayWidth.of("漢字".to_slice)                   # => 4
DisplayWidth.of([0x1F469, 0x200D, 0x1F4BB])        # => 2  👩‍💻
DisplayWidth.of(['1', '\u{FE0F}', '\u{20E3}'])     # => 2  1️⃣
DisplayWidth.of("\e[31mred\e[0m")                 # => 3
```

Ill-formed UTF-8 counts as U+FFFD, one replacement per maximal subpart (as
kitty and the Unicode Standard do).

## Clusters

`DisplayWidth.each_cluster(text) { |offset, size, width| }` yields every cluster
of `text` in order, covering it without gaps. For a `String` or `Bytes`,
`offset` and `size` count bytes; for a sequence of code points, they count code
points.

A cluster is one of:

- the code points a terminal puts in one cell, `width` 1 or 2;
- one C0 control (`\t`, `\n`, `\r`, ...), `width` 0;
- zero-width code points with no cell to join (at the start, or after a
  control), `width` 0;
- a run of [escape sequences](#escape-sequences), `width` 0.

```crystal
DisplayWidth.each_cluster("a\tb") { |o, s, w| p({o, s, w}) }
# {0, 1, 1}
# {1, 1, 0}
# {2, 1, 1}
```

The [column helpers](#columns) truncate, pad and find columns on top of these
clusters.

## Escape sequences

Escape sequences take no cells. They are read as kitty's parser reads them:

| Starts with                                                   | Ends with                                                                          | For example                                        |
|---------------------------------------------------------------|------------------------------------------------------------------------------------|----------------------------------------------------|
| `ESC [` (CSI)                                                 | the first code point after its parameter and intermediate bytes (U+0020 to U+003F) | styles `\e[1;31m`, modes `\e[?2027h`, cursor moves |
| `ESC ]` (OSC), `ESC P` (DCS), `ESC X`, `ESC ^`, `ESC _` (APC) | BEL or ST (`ESC \`)                                                                | hyperlinks, titles, kitty graphics                 |
| `ESC` and one of `% ( ) * + - . / #` or space                 | the code point after that                                                          | character sets `\e(B`                              |
| `ESC` and anything else                                       | that code point                                                                    | `\e7`, `\e8`, `\eM`                                |

A hyperlink's URI is inside its two OSC 8 sequences, and its label between them:

```crystal
link = "\e]8;;https://example.org\e\\docs\e]8;;\e\\"
DisplayWidth.of(link) # => 4
DisplayWidth.each_cluster(link) { |o, s, w| p({o, s, w}) }
# {0, 26, 0}
# {26, 1, 1}
# {27, 1, 1}
# {28, 1, 1}
# {29, 1, 1}
# {30, 7, 0}
```

- An escape sequence leaves the cell before it open: a mark, variation selector
  or joiner after it still joins that cell, as kitty rebuilds its segmentation
  state from the cell before the cursor after every sequence.
  `"\u{263A}\e[0m\u{FE0F}"` takes 2 cells, in one cluster.
- Otherwise a run of escape sequences is a cluster of its own, with no cells.
- Inside a CSI, kitty acts on BEL, BS, HT, LF, VT, FF, CR, SO and SI without
  ending the sequence; they are clusters of their own. Any other code point
  that cannot continue a CSI ends it and is dropped with it, as kitty drops it:
  `"\e[31\e[0m"` takes 3 cells (`[0m`).
- A sequence that never ends takes the rest of the text.
- 8-bit C1 controls (U+009B, ...) start no sequence: kitty only reads 7-bit
  ones.
- The cursor movement a sequence causes is not tracked: measure the text
  between cursor moves.

kitty is stricter about the order of CSI parameter bytes, and gives up on a
sequence after 256 KiB, so malformed or oversized sequences can measure
differently there. `Policy.new(escapes: false)` makes ESC a plain C0 control
and the rest of a sequence text.

## Columns

These helpers lay text out in columns. They measure as `of` does, so a tab
takes no cells; `column` is the one that expands tabs.

| Method                              | Returns                                                                    |
|-------------------------------------|----------------------------------------------------------------------------|
| `fit(text, cells)`                  | `{bytes, width}` of the longest start of `text` that takes at most `cells` |
| `truncate(text, cells, tail = "…")` | `text` cut to at most `cells`, ending in `tail`                            |
| `pad(text, cells, align = :left)`   | `text` padded with spaces to `cells`: `:left`, `:right` or `:center`       |
| `offset_at(text, column)`           | the byte offset of the cluster that covers `column` (from 0)               |
| `column(text, from = 0, tab = 8)`   | the column the cursor reaches after one line of `text`, from `from`        |

```crystal
DisplayWidth.fit("漢字abc", 3)               # => {3, 2}
DisplayWidth.truncate("hello world", 8)    # => "hello w…"
DisplayWidth.truncate("漢字漢字", 6)          # => "漢字…"
DisplayWidth.pad("漢", 4, :right)           # => "  漢"
DisplayWidth.pad("ab", 5, :center)          # => " ab  "
DisplayWidth.offset_at("a漢b", 2)           # => 1
DisplayWidth.column("a\tb")                 # => 9
DisplayWidth.column("\tx", from: 3, tab: 4) # => 5
```

- `fit`, `offset_at` and `column` take a `String` or `Bytes`; `truncate` and
  `pad` take a `String`, and have an `IO` overload that writes the result
  instead: `truncate(io, text, cells, tail)`, `pad(io, text, cells, align)`.
- A wide cluster that does not fit is left out whole, so the result can be a
  cell short.
- `fit` takes in the zero-width clusters before the first cluster that does
  not fit.
- `truncate` and `pad` return `text` itself when it fits. `truncate` keeps the
  escape sequences after the cut, after the tail, so styles and hyperlinks end
  as they would have. It leaves the tail out when the tail does not fit by
  itself.
- `offset_at` skips zero-width clusters, and gives the size of `text` for a
  column past its last cell.
- `column` raises `ArgumentError` when `tab` is less than 1. Controls other
  than tab leave the cursor in place: it is for one line.

```crystal
link = "\e]8;;https://example.org\e\\docs here\e]8;;\e\\"
DisplayWidth.truncate(link, 5) # => "\e]8;;https://example.org\e\\docs…\e]8;;\e\\"
```

## Policy

A `DisplayWidth::Policy` matches the terminal the text is drawn on. Every method
takes one as its last argument, defaulting to `Policy.new`.

| Argument    | Default | Effect                                                                                                                                                                                           |
|-------------|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ambiguous` | `1`     | Cells of an East Asian Ambiguous code point (`±`, `§`, private use, U+FFFD): 1, or 2 as CJK terminals draw them. Marks stay at 0.                                                                |
| `graphemes` | `true`  | `true` follows kitty's algorithm (mode 2027 terminals). `false` follows terminals without grapheme support: every code point with a width starts a cell, and variation selectors change nothing. |
| `escapes`   | `true`  | `true` reads escape sequences as kitty does: they take no cells. `false` makes ESC a plain C0 control, and what follows it text.                                                                 |

```crystal
cjk    = DisplayWidth::Policy.new(ambiguous: 2)
legacy = DisplayWidth::Policy.new(graphemes: false)
raw    = DisplayWidth::Policy.new(escapes: false)

DisplayWidth.of("±", cjk)                             # => 2
DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB}", legacy) # => 4
DisplayWidth.of("\u{263A}\u{FE0F}", legacy)           # => 1
DisplayWidth.of("\e[1mbold\e[0m", raw)                # => 10
```

`Policy.new` raises `ArgumentError` when `ambiguous` is neither 1 nor 2.

## Streams

`DisplayWidth::Stream` measures text that arrives in pieces: UTF-8 chunks split
anywhere (even inside a sequence or an escape sequence), or code points one at a
time. It reports widths in two ways, from the same state.

`write` yields the width of each cluster once it is finished, which is when the
next cluster starts. `flush` ends the text: it yields the open cluster, and an
unfinished UTF-8 sequence becomes U+FFFD.

```crystal
stream = DisplayWidth::Stream.new
stream.write(Bytes[0xE6]) { |w| p w }             # nothing finished yet
stream.write(Bytes[0xBC, 0xA2, 0x61]) { |w| p w } # 2  "漢"
stream.flush { |w| p w }                          # 1  "a"
stream.write('\u{1F469}') { |w| p w }             # code points work too
```

`advance` returns how far the input moved the cursor, as a terminal moves it: a
cluster's cells as it starts, then +1 or −1 when a later code point resizes it.

```crystal
cursor = DisplayWidth::Stream.new
cursor.advance('\u{231A}')                       # => 2   ⌚
cursor.advance('\u{FE0E}')                       # => -1  text presentation
cursor.advance('\u{0E01}')                       # => 1   ก
cursor.advance('\u{0E33}')                       # => 1   SARA AM widens the cell
cursor.advance("\u{1F469}\u{200D}\u{1F4BB} ok") # => 5
cursor.advance("\e]8;;https://exa")              # => 0
cursor.advance("mple.org\e\\link")               # => 4
```

After `flush`, what follows starts with no cell to join, outside any escape
sequence.

## Placing code points

A terminal emulator draws text as it arrives, one code point at a time, and
reads escape sequences itself. `DisplayWidth::Placer` tells it what each code
point does to its cells, by the same rules `of` and `each_cluster` follow.
`put` returns a `Placer::Step`, and `width` is the open cluster's width after it:

| Step    | What the code point did                                                                |
|---------|----------------------------------------------------------------------------------------|
| `Start` | Opened a cluster of `width` cells. With a `width` of 0 it has no cell: drop it         |
| `Join`  | Joined the open cluster; `width` may have changed (VS16, VS15, SARA AM). If 0, drop it |
| `Skip`  | Discarded: an invalid code point while a cluster is open                               |

```crystal
placer = DisplayWidth::Placer.new
placer.put('\u{2764}') # => Start, placer.width == 1: a cell of one column
placer.put(0xFE0F)     # => Join, placer.width == 2: widen that cell
placer.reset           # the cursor moved: nothing joins that cell any more
placer.put(0x301)      # => Start, placer.width == 0: no cell to join, drop it
```

`reset` it wherever the cell it holds stops being the one before the cursor.
`policy=` switches policies (for mode 2027) from the next code point on.

For a fast path, `DisplayWidth.props(codepoint)` gives a code point's
`Props`, and `Policy#cells(props)` its cells. While `Placer#plain?`, a code
point whose `Props#plain?` holds (and is not `Props#invalid?`) starts a cell
of its own; `Placer#plain!(codepoint, width)` records it without a full step.

## How cells are counted

The width of one code point follows kitty's rules, highest priority first:

| Width  | Code points                                                                                                              |
|--------|--------------------------------------------------------------------------------------------------------------------------|
| 2      | Regional indicators; East Asian Wide and Fullwidth (and the CJK ideograph planes); wide emoji from `emoji-sequences.txt` |
| 0      | Marks (`M*`), format characters (`Cf`), `Other_Default_Ignorable_Code_Point` (U+3099, a wide mark, stays 2)              |
| 1 or 2 | East Asian Ambiguous, by `Policy#ambiguous`                                                                              |
| 1      | Everything else, including unassigned and private use code points                                                        |

C0 controls take 0 cells and form a cluster of their own. DEL, C1 controls,
surrogates and noncharacters are discarded: they take no cells, join the
cluster before them, and leave segmentation untouched.

Text is then placed cluster by cluster:

- A code point that does not start a grapheme cluster (UAX #29) joins the
  current cell, and so does a zero-width code point that does.
- A zero-width code point with no cell to join (at the start of the text, or
  after a control) takes no cells. The text is measured as if it started a
  line.
- U+FE0F (VS16) after an emoji presentation base widens a 1-cell cell to 2;
  U+FE0E (VS15) after one narrows a 2-cell cell to 1.
- A spacing mark with a width of its own (Thai and Lao SARA AM) widens a 1-cell
  cell to 2.
- Escape sequences take no cells and leave the current cell open.

Kitty's `wcswidth` lets a cluster that starts with a zero-width code point take
what follows, where its drawing code and this shard start a new cell (for
example `"\u{0600}a"`). It also predates Unicode 18's revised rule GB9c.

## Performance

`make bench` measures lines of about 80 columns on an Intel i5-1240P, pinned
to one performance core. The styled line holds ten escape sequences: styles
and an OSC 8 hyperlink.

| Line (bytes)   | `of(String)` | `each_cluster` | `Stream#advance` |
|----------------|--------------|----------------|------------------|
| ASCII (85)     | 13 ns        | 42 ns          | 39 ns            |
| Latin (85)     | 88 ns        | 106 ns         | 98 ns            |
| CJK (117)      | 208 ns       | 224 ns         | 233 ns           |
| emoji (135)    | 361 ns       | 362 ns         | 335 ns           |
| combining (55) | 209 ns       | 207 ns         | 206 ns           |
| styled (149)   | 223 ns       | 225 ns         | 191 ns           |

None of them allocates (`Stream.new` allocates the stream once). For comparison,
the standard library's `String#each_grapheme` takes 1.4 to 6.3 µs on the same
lines without measuring widths.

## Updating Unicode

The tables live in `data/tables.bin` (about 34 KB), embedded at compile time.
`make tables` regenerates it, with the conformance data in `spec/data`, from
unicode.org; `make tables UCD=dir` reads a local mirror of
`Public/<version>/` instead. The Unicode version is `UNICODE_VERSION` in
`tools/gen_tables.cr`; `DisplayWidth::UNICODE_VERSION` reports the version
the tables were built from.
