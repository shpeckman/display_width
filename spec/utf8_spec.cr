# spec/utf8_spec.cr
require "./spec_helper"

describe "ill-formed UTF-8" do
  it "replaces a stray byte with U+FFFD" do
    clusters(Bytes[0x61, 0xFF, 0x62]).should eq([{0, 1, 1}, {1, 1, 1}, {2, 1, 1}])
    clusters(Bytes[0x80]).should eq([{0, 1, 1}])
    clusters(Bytes[0x9F, 0x80]).should eq([{0, 1, 1}, {1, 1, 1}])
    clusters(Bytes[0xF8, 0x88, 0x80, 0x80]).size.should eq(4)
    clusters(Bytes[0xF5, 0x80, 0x80, 0x80]).size.should eq(4)
  end

  it "replaces a sequence cut off at the end with one U+FFFD" do
    clusters(Bytes[0xE2, 0x82]).should eq([{0, 2, 1}])
    clusters(Bytes[0xF0, 0x9F, 0x98]).should eq([{0, 3, 1}])
  end

  it "replaces each maximal subpart" do
    clusters(Bytes[0xE2, 0x82, 0x41]).should eq([{0, 2, 1}, {2, 1, 1}])
    clusters(Bytes[0xF0, 0x80, 0x80]).should eq([{0, 1, 1}, {1, 1, 1}, {2, 1, 1}])
    clusters(Bytes[0xED, 0xA0, 0x80]).should eq([{0, 1, 1}, {1, 1, 1}, {2, 1, 1}])
    clusters(Bytes[0xC0, 0xAF]).should eq([{0, 1, 1}, {1, 1, 1}])
    clusters(Bytes[0xF4, 0x90, 0x80, 0x80]).size.should eq(4)
  end

  it "decodes every well-formed length" do
    clusters("a").should eq([{0, 1, 1}])
    clusters("é").should eq([{0, 2, 1}])
    clusters("漢").should eq([{0, 3, 2}])
    clusters("😀").should eq([{0, 4, 2}])
    clusters("\u{10FFFD}").should eq([{0, 4, 1}])
  end

  it "gives U+FFFD the ambiguous width" do
    DisplayWidth.of(Bytes[0xFF], WIDE).should eq(2)
  end
end
