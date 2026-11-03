# spec/escape_spec.cr
require "./spec_helper"

describe "escape sequences" do
  it "take no cells" do
    DisplayWidth.of("\e[31mred\e[0m").should eq(3)
    DisplayWidth.of("\e[38;2;255;0;0mx").should eq(1)
    DisplayWidth.of("\e[?2026h\e[?2026l").should eq(0)
    DisplayWidth.of("\e[1 qx").should eq(1)
    DisplayWidth.of("\e[4:3m\e[58:5:1mx").should eq(1)
  end

  it "leave an OSC 8 hyperlink's label and take its URI" do
    link = "\e]8;;https://x.org\e\\docs\e]8;;\e\\"
    DisplayWidth.of(link).should eq(4)
    clusters(link).should eq([{0, 20, 0}, {20, 1, 1}, {21, 1, 1}, {22, 1, 1}, {23, 1, 1}, {24, 7, 0}])
    DisplayWidth.of("\e]8;id=1;https://x.org\e\\漢字\e]8;;\e\\").should eq(4)
  end

  it "end a string at BEL" do
    clusters("\e]0;title\ax").should eq([{0, 10, 0}, {10, 1, 1}])
  end

  it "keep an ESC that does not start ST inside the string" do
    DisplayWidth.of("\e]0;a\eb\e\\x").should eq(1)
    DisplayWidth.of("\e]0;a\e\e\\x").should eq(1)
    DisplayWidth.of("\e]0;a\e\ax").should eq(1)
  end

  it "end strings of every kind" do
    {'P', 'X', '^', '_'}.each do |kind|
      DisplayWidth.of("\e#{kind}payload\e\\x").should eq(1)
    end
  end

  it "run a string over any bytes" do
    DisplayWidth.of("\e]2;漢字\a漢").should eq(2)
    DisplayWidth.of(Bytes[0x1B, 0x5D, 0x32, 0x3B, 0xFF, 0xE6, 0xBC, 0x07, 0x61]).should eq(1)
    payload = "\e_Ga=T,f=100;" + "QUJD" * 64 + "\e\\"
    clusters(payload + "ok").should eq([{0, payload.bytesize, 0}, {payload.bytesize, 1, 1}, {payload.bytesize + 1, 1, 1}])
  end

  it "end a CSI at its final byte, or drop the code point that does not belong to it, as kitty does" do
    DisplayWidth.of("\e[31\e[0m").should eq(3)
    DisplayWidth.of("\e[1漢x").should eq(1)
    DisplayWidth.of("\e[1\u{0301}x").should eq(1)
  end

  it "let controls inside a CSI act, as kitty does" do
    clusters("\e[3\t1mX").should eq([{0, 3, 0}, {3, 1, 0}, {4, 2, 0}, {6, 1, 1}])
    clusters("\e[3\t12;4mX").should eq([{0, 3, 0}, {3, 1, 0}, {4, 5, 0}, {9, 1, 1}])
    clusters("\e[\t\tm").should eq([{0, 2, 0}, {2, 1, 0}, {3, 1, 0}, {4, 1, 0}])
    clusters("\e[\t").should eq([{0, 2, 0}, {2, 1, 0}])
  end

  it "take one more code point after an intermediate" do
    DisplayWidth.of("\e(Bx").should eq(1)
    DisplayWidth.of("\e#8").should eq(0)
    clusters("\e(0x").should eq([{0, 3, 0}, {3, 1, 1}])
  end

  it "take any code point after ESC, as kitty does" do
    clusters("\e\nx").should eq([{0, 2, 0}, {2, 1, 1}])
    DisplayWidth.of("\e\e[1m").should eq(3)
    DisplayWidth.of("\e7x\e8").should eq(1)
  end

  it "leave the cell before them open" do
    clusters("e\e[1m\u{0301}").should eq([{0, 7, 1}])
    DisplayWidth.of("\u{263A}\e[0m\u{FE0F}").should eq(2)
    DisplayWidth.of("\u{231A}\e[0m\u{FE0E}").should eq(1)
    DisplayWidth.of("\u{1F469}\e[1m\u{200D}\e[2m\u{1F4BB}").should eq(2)
    DisplayWidth.of("\u{0E01}\e[0m\u{0E33}").should eq(2)
    DisplayWidth.of("\u{1F1F3}\e[0m\u{1F1F1}").should eq(2)
  end

  it "become a cluster of their own when the next code point starts one" do
    clusters("a\e[1mb").should eq([{0, 1, 1}, {1, 4, 0}, {5, 1, 1}])
    clusters("a\e[1m\e]8;;u\e\\b").should eq([{0, 1, 1}, {1, 12, 0}, {13, 1, 1}])
    clusters("a\e[0m").should eq([{0, 1, 1}, {1, 4, 0}])
    clusters("\e[1m\u{0301}").should eq([{0, 4, 0}, {4, 2, 0}])
    clusters("\t\e[0m\u{0301}").should eq([{0, 1, 0}, {1, 4, 0}, {5, 2, 0}])
  end

  it "keep discarded code points after them in their cluster" do
    clusters("a\e[0m\u{007F}b").should eq([{0, 1, 1}, {1, 5, 0}, {6, 1, 1}])
  end

  it "take the rest of the text when unterminated" do
    DisplayWidth.of("\e]8;;https://x.org docs").should eq(0)
    clusters("ab\e[").should eq([{0, 1, 1}, {1, 1, 1}, {2, 2, 0}])
  end

  it "cover the text without gaps and sum to its width" do
    text = "\e[1mGröße\e[0m \e]8;;https://x.org\e\\漢字\e]8;;\e\\ e\e[3m\u{0301} \e[31\tx\e(B" \
           "\u{1F469}\u{200D}\u{1F4BB}\e]0;t\a \e\e[1m\u{007F}"
    offset = 0
    total = 0
    DisplayWidth.each_cluster(text) do |start, size, width|
      start.should eq(offset)
      offset += size
      total += width
    end
    offset.should eq(text.bytesize)
    total.should eq(DisplayWidth.of(text))
    total.should eq(DisplayWidth::Stream.new.advance(text))
  end

  it "are text when the policy turns them off" do
    DisplayWidth.of("\e[31mred\e[0m", RAW).should eq(10)
    clusters("\e[1m", RAW).should eq([{0, 1, 0}, {1, 1, 1}, {2, 1, 1}, {3, 1, 1}])
  end

  it "work in code point sequences" do
    DisplayWidth.of(['\e', '[', '1', 'm', 'x']).should eq(1)
    found = [] of {Int32, Int32, Int32}
    DisplayWidth.each_cluster(['a', '\e', '[', 'm', 'b']) { |i, n, w| found << {i, n, w} }
    found.should eq([{0, 1, 1}, {1, 3, 0}, {4, 1, 1}])
  end

  describe "in a stream" do
    it "are read across chunks" do
      stream = DisplayWidth::Stream.new
      stream.advance("\e[3").should eq(0)
      stream.advance("1mab").should eq(2)
      stream.advance("\e]8;;https://").should eq(0)
      stream.advance("x.org\e").should eq(0)
      stream.advance("\\docs").should eq(4)
      stream.advance('\e').should eq(0)
      stream.advance('[').should eq(0)
      stream.advance('m').should eq(0)
      stream.advance('x').should eq(1)
    end

    it "are yielded as clusters of no cells" do
      widths(DisplayWidth::Stream.new) { |stream, found| stream.write("a\e[1mb") { |w| found << w } }.should eq([1, 0, 1])
    end

    it "end at flush" do
      stream = DisplayWidth::Stream.new
      stream.advance("\e]0;title").should eq(0)
      stream.flush { }
      stream.advance("x").should eq(1)
    end
  end
end
