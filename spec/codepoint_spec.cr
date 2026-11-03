# spec/codepoint_spec.cr
require "./spec_helper"

describe "DisplayWidth.of(codepoint)" do
  it "reports the tables' Unicode version" do
    DisplayWidth::UNICODE_VERSION.should eq("18.0.0")
  end

  it "gives printable ASCII one cell" do
    (0x20..0x7E).each { |cp| DisplayWidth.of(cp).should eq(1) }
  end

  it "gives controls and invalid code points no cells" do
    {0x00, 0x09, 0x0A, 0x1B, 0x7F, 0x85, 0x9F, 0xD800, 0xDFFF, 0xFDD0, 0xFFFE, 0xFFFF, 0x10FFFF}.each do |cp|
      DisplayWidth.of(cp).should eq(0)
    end
  end

  it "gives values outside the code space no cells" do
    DisplayWidth.of(0x110000).should eq(0)
    DisplayWidth.of(-1).should eq(0)
    DisplayWidth.of(0xFFFFFFFF_u32).should eq(0)
  end

  it "takes Char, Int32 and UInt32 alike" do
    DisplayWidth.of('漢').should eq(2)
    DisplayWidth.of(0x6F22).should eq(2)
    DisplayWidth.of(0x6F22_u32).should eq(2)
  end

  it "gives East Asian Wide and Fullwidth code points two cells" do
    {'漢', '가', 'か', 'Ａ', '\u{20000}', '\u{3FFFD}', '\u{1100}'}.each { |char| DisplayWidth.of(char).should eq(2) }
  end

  it "gives wide emoji, regional indicators and skin tones two cells" do
    {'\u{1F600}', '\u{231A}', '\u{1F1F3}', '\u{1F3FB}', '\u{1F3F4}'}.each { |char| DisplayWidth.of(char).should eq(2) }
  end

  it "gives text-default emoji one cell" do
    {'\u{263A}', '\u{00A9}', '\u{2764}', '1'}.each { |char| DisplayWidth.of(char).should eq(1) }
  end

  it "gives marks, format characters and default ignorables no cells" do
    {'\u{0301}', '\u{20E3}', '\u{200B}', '\u{200D}', '\u{FE0F}', '\u{00AD}', '\u{0600}', '\u{E0067}', '\u{1160}', '\u{FFA0}'}.each do |char|
      DisplayWidth.of(char).should eq(0)
    end
  end

  it "lets East Asian Wide win over marks, as kitty does" do
    DisplayWidth.of('\u{3099}').should eq(2)
  end

  it "gives Hangul medial and final jamo one cell" do
    DisplayWidth.of('\u{1161}').should eq(1)
    DisplayWidth.of('\u{11A8}').should eq(1)
  end

  it "widens East Asian Ambiguous code points by policy" do
    {'±', '\u{E000}', '\u{FFFD}'}.each do |char|
      DisplayWidth.of(char).should eq(1)
      DisplayWidth.of(char, WIDE).should eq(2)
    end
  end

  it "keeps ambiguous marks at no cells" do
    DisplayWidth.of('\u{0300}', WIDE).should eq(0)
  end

  it "gives unassigned code points one cell" do
    DisplayWidth.of(0x0378).should eq(1)
  end
end
