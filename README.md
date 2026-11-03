# display_width

How many terminal cells a code point or a piece of text takes: 0, 1 or 2 per
cluster. It uses the Unicode 18.0.0 tables, segments text into grapheme
clusters (UAX #29 revision 49), and places them in cells by
[kitty's algorithm for splitting text into cells](https://sw.kovidgoyal.net/kitty/text-sizing-protocol/#the-algorithm-for-splitting-text-into-cells).
Input can be code points or UTF-8 bytes, whole or as a stream.

It is built for TUIs: nothing allocates, printable ASCII is measured eight bytes
at a time, and the tables are embedded at compile time.

```crystal
require "display_width"

DisplayWidth.of('漢')                             # => 2
DisplayWidth.of("e\u{0301}")                     # => 1
DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB} ok") # => 5  👩‍💻 ok

DisplayWidth.each_cluster("a\u{1F44D}\u{1F3FD}") do |offset, size, width|
  # {0, 1, 1}, then {1, 8, 2}
end
```

## Contents

- [Installation](#installation)
- [Code points](#code-points)
- [Text](#text)
- [Clusters](#clusters)
- [Policy](#policy)
- [Streams](#streams)
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
- one C0 control (`\t`, `\n`, `\e`, ...), `width` 0;
- zero-width code points with no cell to join (at the start, or after a
  control), `width` 0.

```crystal
DisplayWidth.each_cluster("a\tb") { |o, s, w| p({o, s, w}) }
# {0, 1, 1}
# {1, 1, 0}
# {2, 1, 1}
```

That makes truncating and padding to a number of columns a loop over
`each_cluster`, slicing at `offset`.

## Policy

A `DisplayWidth::Policy` matches the terminal the text is drawn on. Every method
takes one as its last argument, defaulting to `Policy.new`.

| Argument    | Default | Effect                                                                                                                                                                                             |
|-------------|---------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ambiguous` | `1`     | Cells of an East Asian Ambiguous code point (`±`, `§`, private use, U+FFFD): 1, or 2 as CJK terminals draw them. Marks stay at 0.                                                                  |
| `graphemes` | `true`  | `true` follows kitty's algorithm (mode 2027 terminals). `false` follows terminals without grapheme support: every code point with a width starts a cell, and variation selectors change nothing. |

```crystal
cjk    = DisplayWidth::Policy.new(ambiguous: 2)
legacy = DisplayWidth::Policy.new(graphemes: false)

DisplayWidth.of("±", cjk)                             # => 2
DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB}", legacy) # => 4
DisplayWidth.of("\u{263A}\u{FE0F}", legacy)           # => 1
```

`Policy.new` raises `ArgumentError` when `ambiguous` is neither 1 nor 2.

## Streams

`DisplayWidth::Stream` measures text that arrives in pieces: UTF-8 chunks split
anywhere (even inside a sequence), or code points one at a time. It reports
widths in two ways, from the same state.

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
```

After `flush`, what follows starts with no cell to join.

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

Kitty's `wcswidth` lets a cluster that starts with a zero-width code point take
what follows, where its drawing code and this shard start a new cell (for
example `"\u{0600}a"`). It also predates Unicode 18's revised rule GB9c.

## Performance

`make bench` measures lines of about 80 columns on an Intel i5-1240P:

| Line (bytes)   | `of(String)` | `each_cluster` | `Stream#advance` |
|----------------|--------------|----------------|------------------|
| ASCII (85)     | 13 ns        | 41 ns          | 47 ns            |
| Latin (85)     | 72 ns        | 93 ns          | 119 ns           |
| CJK (117)      | 197 ns       | 229 ns         | 233 ns           |
| emoji (135)    | 326 ns       | 297 ns         | 403 ns           |
| combining (55) | 188 ns       | 178 ns         | 207 ns           |

None of them allocates (`Stream.new` allocates the stream once). For comparison,
the standard library's `String#each_grapheme` takes 1.3 to 3.4 µs on the same
lines without measuring widths.

## Updating Unicode

The tables live in `data/tables.bin` (about 34 KB), embedded at compile time.
`make tables` regenerates it, with the conformance data in `spec/data`, from
unicode.org; `make tables UCD=dir` reads a local mirror of
`Public/<version>/` instead. The Unicode version is `UNICODE_VERSION` in
`tools/gen_tables.cr`; `DisplayWidth::UNICODE_VERSION` reports the version
the tables were built from.
