# spec/text_spec.cr
require "./spec_helper"

describe "DisplayWidth.of(text)" do
  it "sums plain text" do
    DisplayWidth.of("").should eq(0)
    DisplayWidth.of("hello").should eq(5)
    DisplayWidth.of("漢字").should eq(4)
    DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB} ok").should eq(5)
  end

  it "measures String and Bytes alike" do
    DisplayWidth.of("a漢😀".to_slice).should eq(5)
  end

  it "joins combining marks to their base" do
    DisplayWidth.of("e\u{0301}").should eq(1)
    DisplayWidth.of("e\u{0301}\u{0302}\u{0303}").should eq(1)
  end

  it "takes emoji sequences as one wide cell" do
    DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB}").should eq(2)
    DisplayWidth.of("\u{1F1F3}\u{1F1F1}").should eq(2)
    DisplayWidth.of("\u{1F44B}\u{1F3FB}").should eq(2)
    DisplayWidth.of("\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}").should eq(2)
  end

  it "gives a lone regional indicator two cells" do
    DisplayWidth.of("\u{1F1F3}").should eq(2)
    DisplayWidth.of("\u{1F1F3}\u{1F1F1}\u{1F1E7}").should eq(4)
  end

  it "widens an emoji presentation base with VS16" do
    DisplayWidth.of("\u{263A}").should eq(1)
    DisplayWidth.of("\u{263A}\u{FE0F}").should eq(2)
    DisplayWidth.of("1\u{FE0F}\u{20E3}").should eq(2)
  end

  it "narrows a wide emoji presentation base with VS15" do
    DisplayWidth.of("\u{231A}").should eq(2)
    DisplayWidth.of("\u{231A}\u{FE0E}").should eq(1)
  end

  it "leaves other bases alone" do
    DisplayWidth.of("a\u{FE0F}").should eq(1)
    DisplayWidth.of("漢\u{FE0E}").should eq(2)
    DisplayWidth.of("\u{263A}\u{FE0F}\u{FE0F}").should eq(2)
  end

  it "widens a narrow cell with a spacing mark that has a width (SARA AM)" do
    DisplayWidth.of("\u{0E01}\u{0E33}").should eq(2)
    DisplayWidth.of("\u{0E81}\u{0EB3}").should eq(2)
    DisplayWidth.of("\u{0915}\u{093F}").should eq(1)
  end

  it "takes Hangul jamo sequences as one syllable" do
    DisplayWidth.of("\u{1100}\u{1161}\u{11A8}").should eq(2)
  end

  it "keeps Indic conjuncts in one cell (GB9c)" do
    clusters("\u{0915}\u{094D}\u{0937}").should eq([{0, 9, 1}])
    clusters("\u{0915}\u{094D}\u{200D}\u{0937}").should eq([{0, 12, 1}])
  end

  it "counts controls as no cells" do
    DisplayWidth.of("a\tb\r\n").should eq(2)
  end

  it "joins zero-width code points to the cell before them" do
    clusters("a\u{200B}b").should eq([{0, 4, 1}, {4, 1, 1}])
  end

  it "joins what follows a prepended mark to its cell, as kitty does" do
    clusters("x\u{0600}a").should eq([{0, 4, 1}])
  end

  it "keeps zero-width code points with no cell to join in a cluster of their own" do
    clusters("\u{0301}a").should eq([{0, 2, 0}, {2, 1, 1}])
    clusters("\u{0301}\u{0302}").should eq([{0, 4, 0}])
    clusters("\n\u{0301}").should eq([{0, 1, 0}, {1, 2, 0}])
    clusters("\u{0600}a").should eq([{0, 2, 0}, {2, 1, 1}])
  end

  it "makes each C0 control a cluster" do
    clusters("a\tb").should eq([{0, 1, 1}, {1, 1, 0}, {2, 1, 1}])
    clusters("\r\n").should eq([{0, 1, 0}, {1, 1, 0}])
  end

  it "keeps discarded code points inside the cluster before them" do
    clusters("a\u{007F}b").should eq([{0, 2, 1}, {2, 1, 1}])
    clusters("e\u{0085}\u{0301}").should eq([{0, 5, 1}])
    clusters("\u{0085}").should eq([{0, 2, 0}])
    clusters("\t\u{007F}").should eq([{0, 1, 0}, {1, 1, 0}])
  end

  it "splits printable ASCII runs into one-cell clusters" do
    clusters("abcdefghij").should eq((0...10).map { |i| {i, 1, 1} })
  end

  it "lets the last byte of an ASCII run take what follows" do
    found = clusters("abcdefghij\u{0301}")
    found.size.should eq(10)
    found.last.should eq({9, 3, 1})
    DisplayWidth.of("abcdefgh1\u{FE0F}\u{20E3}").should eq(10)
  end

  it "covers the text without gaps and sums to its width" do
    text = "Größe 漢字 \u{1F469}\u{200D}\u{1F4BB} e\u{0301} \u{1F1F3}\u{1F1F1}\u{1F1E7} \u{263A}\u{FE0F}\tx\u{0600}a \u{0085} \u{0915}\u{094D}\u{0937}"
    offset = 0
    total = 0
    DisplayWidth.each_cluster(text) do |start, size, width|
      start.should eq(offset)
      offset += size
      total += width
    end
    offset.should eq(text.bytesize)
    total.should eq(DisplayWidth.of(text))
  end

  it "widens ambiguous code points by policy" do
    DisplayWidth.of("±§", WIDE).should eq(4)
  end

  describe "without graphemes" do
    it "sums code point widths" do
      DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB}", LEGACY).should eq(4)
      DisplayWidth.of("\u{1F1F3}\u{1F1F1}", LEGACY).should eq(4)
      DisplayWidth.of("\u{0E01}\u{0E33}", LEGACY).should eq(2)
      DisplayWidth.of("\u{1100}\u{1161}\u{11A8}", LEGACY).should eq(4)
    end

    it "ignores variation selectors" do
      DisplayWidth.of("\u{263A}\u{FE0F}", LEGACY).should eq(1)
      DisplayWidth.of("\u{231A}\u{FE0E}", LEGACY).should eq(2)
      DisplayWidth.of("1\u{FE0F}\u{20E3}", LEGACY).should eq(1)
    end

    it "joins zero-width code points to the cell before them" do
      DisplayWidth.of("e\u{0301}", LEGACY).should eq(1)
      clusters("\u{1F469}\u{200D}\u{1F4BB}", LEGACY).should eq([{0, 7, 2}, {7, 4, 2}])
    end
  end

  describe "of code point sequences" do
    it "measures Char, Int32 and UInt32 sequences" do
      DisplayWidth.of(['e', '\u{0301}']).should eq(1)
      DisplayWidth.of([0x1F469, 0x200D, 0x1F4BB]).should eq(2)
      DisplayWidth.of(Slice[0x31_u32, 0xFE0F_u32, 0x20E3_u32]).should eq(2)
      DisplayWidth.of([] of Char).should eq(0)
    end

    it "yields clusters in code point indices" do
      found = [] of {Int32, Int32, Int32}
      DisplayWidth.each_cluster(['a', 'e', '\u{0301}', '\u{1F469}', '\u{200D}', '\u{1F4BB}']) { |i, n, w| found << {i, n, w} }
      found.should eq([{0, 1, 1}, {1, 2, 1}, {3, 3, 2}])
    end

    it "treats invalid values as discarded code points" do
      DisplayWidth.of([0x61, 0xD800, 0x110000]).should eq(1)
    end
  end
end
