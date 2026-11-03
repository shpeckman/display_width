# spec/layout_spec.cr
require "./spec_helper"

describe "DisplayWidth.fit" do
  it "finds the longest start that fits" do
    DisplayWidth.fit("hello", 3).should eq({3, 3})
    DisplayWidth.fit("hello", 10).should eq({5, 5})
    DisplayWidth.fit("", 3).should eq({0, 0})
    DisplayWidth.fit("abc", 0).should eq({0, 0})
  end

  it "leaves out a wide cluster that does not fit" do
    DisplayWidth.fit("漢字abc", 3).should eq({3, 2})
    DisplayWidth.fit("漢字abc", 4).should eq({6, 4})
  end

  it "keeps clusters whole" do
    DisplayWidth.fit("e\u{0301}x", 1).should eq({3, 1})
    DisplayWidth.fit("\u{1F469}\u{200D}\u{1F4BB}x", 1).should eq({0, 0})
  end

  it "takes in zero-width clusters before the first that does not fit" do
    DisplayWidth.fit("ab\e[0mcd", 2).should eq({6, 2})
    DisplayWidth.fit("\e[1mab", 0).should eq({4, 0})
  end

  it "measures Bytes alike" do
    DisplayWidth.fit("漢字".to_slice, 3).should eq({3, 2})
  end
end

describe "DisplayWidth.truncate" do
  it "cuts text that does not fit and ends it in the tail" do
    DisplayWidth.truncate("hello world", 8).should eq("hello w…")
    DisplayWidth.truncate("hello world", 8, "...").should eq("hello...")
    DisplayWidth.truncate("hello world", 5, "").should eq("hello")
  end

  it "returns text that fits as it is" do
    text = "hello"
    DisplayWidth.truncate(text, 5).should be(text)
    DisplayWidth.truncate(text, 9).should be(text)
  end

  it "does not split a wide cluster" do
    DisplayWidth.truncate("漢字漢字", 6).should eq("漢字…")
    DisplayWidth.truncate("漢字漢字", 7).should eq("漢字漢…")
  end

  it "leaves out a tail that does not fit by itself" do
    DisplayWidth.truncate("hello", 0).should eq("")
    DisplayWidth.truncate("hello", 2, "...").should eq("he")
    DisplayWidth.truncate("hello", 3, "...").should eq("...")
  end

  it "keeps the escape sequences after the cut" do
    DisplayWidth.truncate("\e[31mred alert\e[0m", 4).should eq("\e[31mred…\e[0m")
    link = "\e]8;;https://x.org\e\\docs here\e]8;;\e\\"
    DisplayWidth.truncate(link, 5).should eq("\e]8;;https://x.org\e\\docs…\e]8;;\e\\")
    DisplayWidth.truncate("a\e[1mb\e[2mc\e[0m", 1, "").should eq("a\e[1m\e[2m\e[0m")
  end

  it "keeps nothing after the cut when the policy turns escape sequences off" do
    DisplayWidth.truncate("abc\e[0m", 2, "", RAW).should eq("ab")
  end

  it "writes to an IO" do
    String.build { |io| DisplayWidth.truncate(io, "hello world", 8) }.should eq("hello w…")
    String.build { |io| DisplayWidth.truncate(io, "hello", 8) }.should eq("hello")
  end

  it "follows the policy" do
    DisplayWidth.truncate("±±±", 3, "", WIDE).should eq("±")
  end
end

describe "DisplayWidth.pad" do
  it "pads to a number of cells" do
    DisplayWidth.pad("漢", 4).should eq("漢  ")
    DisplayWidth.pad("漢", 4, :right).should eq("  漢")
    DisplayWidth.pad("ab", 5, :center).should eq(" ab  ")
    DisplayWidth.pad("e\u{0301}", 3).should eq("e\u{0301}  ")
  end

  it "returns text that takes the cells or more as it is" do
    text = "hello"
    DisplayWidth.pad(text, 5).should be(text)
    DisplayWidth.pad(text, 3).should be(text)
  end

  it "pads after escape sequences" do
    DisplayWidth.pad("\e[1mab\e[0m", 4).should eq("\e[1mab\e[0m  ")
  end

  it "writes to an IO" do
    String.build { |io| DisplayWidth.pad(io, "ab", 4, :right) }.should eq("  ab")
    String.build { |io| DisplayWidth.pad(io, "hello", 3, :center) }.should eq("hello")
  end

  it "follows the policy" do
    DisplayWidth.pad("±", 3, policy: WIDE).should eq("± ")
  end
end

describe "DisplayWidth.offset_at" do
  it "finds the cluster that covers a column" do
    DisplayWidth.offset_at("a漢b", 0).should eq(0)
    DisplayWidth.offset_at("a漢b", 1).should eq(1)
    DisplayWidth.offset_at("a漢b", 2).should eq(1)
    DisplayWidth.offset_at("a漢b", 3).should eq(4)
  end

  it "gives the size of the text past its last cell" do
    DisplayWidth.offset_at("a漢b", 4).should eq(5)
    DisplayWidth.offset_at("", 0).should eq(0)
  end

  it "skips zero-width clusters" do
    DisplayWidth.offset_at("\e[1mab", 0).should eq(4)
    DisplayWidth.offset_at("a\tb", 1).should eq(2)
  end

  it "measures Bytes alike" do
    DisplayWidth.offset_at("a漢b".to_slice, 2).should eq(1)
  end
end

describe "DisplayWidth.column" do
  it "moves a tab to the next tab stop" do
    DisplayWidth.column("a\tb").should eq(9)
    DisplayWidth.column("\t\t").should eq(16)
    DisplayWidth.column("abcdefgh\tx").should eq(17)
    DisplayWidth.column("漢\t").should eq(8)
  end

  it "starts from a column" do
    DisplayWidth.column("\tx", from: 3).should eq(9)
    DisplayWidth.column("ab", from: 5).should eq(7)
  end

  it "takes the tab stop interval" do
    DisplayWidth.column("a\tb", tab: 4).should eq(5)
    DisplayWidth.column("a\tb", tab: 1).should eq(3)
  end

  it "leaves other controls and escape sequences in place" do
    DisplayWidth.column("a\rb\n").should eq(2)
    DisplayWidth.column("\e[1m\tx\e[0m").should eq(9)
    DisplayWidth.column("\e[3\t1mX").should eq(9)
  end

  it "raises on a tab stop interval below 1" do
    expect_raises(ArgumentError, "tab stops must be at least 1 column apart, not 0") { DisplayWidth.column("a", tab: 0) }
  end

  it "measures Bytes alike" do
    DisplayWidth.column("a\tb".to_slice).should eq(9)
  end
end
