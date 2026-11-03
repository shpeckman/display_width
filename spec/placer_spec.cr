# spec/placer_spec.cr
require "./spec_helper"

# Steps and widths of *codepoints* put one by one.
def steps(codepoints : Array(Int32), placer = DisplayWidth::Placer.new) : Array({DisplayWidth::Placer::Step, Int32})
  codepoints.map { |codepoint| {placer.put(codepoint), placer.width} }
end

# Cells the clusters of *text* take, from a placer's steps as a terminal would place them.
def placed(text : String, policy = DisplayWidth::Policy.new) : Int32
  placer = DisplayWidth::Placer.new(policy)
  done = 0
  text.each_char do |char|
    before = placer.width
    done += before if placer.put(char).start?
  end
  done + placer.width
end

describe DisplayWidth::Placer do
  it "starts a cell per code point with a width" do
    steps(['a'.ord, 0x6F22, 'b'.ord]).should eq([{DisplayWidth::Placer::Step::Start, 1},
                                                 {DisplayWidth::Placer::Step::Start, 2},
                                                 {DisplayWidth::Placer::Step::Start, 1}])
  end

  it "joins combining marks and emoji sequences to the open cell" do
    steps([0x65, 0x301, 0x302]).map(&.[0]).should eq([DisplayWidth::Placer::Step::Start,
                                                      DisplayWidth::Placer::Step::Join,
                                                      DisplayWidth::Placer::Step::Join])
    steps([0x1F469, 0x200D, 0x1F4BB]).should eq([{DisplayWidth::Placer::Step::Start, 2},
                                                 {DisplayWidth::Placer::Step::Join, 2},
                                                 {DisplayWidth::Placer::Step::Join, 2}])
  end

  it "changes the width of the open cell on VS16, VS15 and SARA AM" do
    steps([0x263A, 0xFE0F]).should eq([{DisplayWidth::Placer::Step::Start, 1}, {DisplayWidth::Placer::Step::Join, 2}])
    steps([0x231A, 0xFE0E]).should eq([{DisplayWidth::Placer::Step::Start, 2}, {DisplayWidth::Placer::Step::Join, 1}])
    steps([0x0E01, 0x0E33]).should eq([{DisplayWidth::Placer::Step::Start, 1}, {DisplayWidth::Placer::Step::Join, 2}])
  end

  it "opens no cell for zero-width code points with nothing to join" do
    steps([0x301, 0x302, 'a'.ord]).should eq([{DisplayWidth::Placer::Step::Start, 0},
                                              {DisplayWidth::Placer::Step::Join, 0},
                                              {DisplayWidth::Placer::Step::Start, 1}])
  end

  it "starts a cell after a zero-width code point even where segmentation joins (kitty's screen.c)" do
    steps([0x200D, 0x1F4BB]).should eq([{DisplayWidth::Placer::Step::Start, 0}, {DisplayWidth::Placer::Step::Start, 2}])
  end

  it "skips invalid code points while a cluster is open" do
    steps(['a'.ord, 0x7F, 0x85, 0xFFFE, 0x301]).map(&.[0]).should eq([DisplayWidth::Placer::Step::Start,
                                                                      DisplayWidth::Placer::Step::Skip,
                                                                      DisplayWidth::Placer::Step::Skip,
                                                                      DisplayWidth::Placer::Step::Skip,
                                                                      DisplayWidth::Placer::Step::Join])
    steps([0x7F]).should eq([{DisplayWidth::Placer::Step::Start, 0}])
    DisplayWidth::Placer.new.put(0x110000_u32).should eq(DisplayWidth::Placer::Step::Start)
  end

  it "takes a C0 control as a cluster of no cells that nothing joins" do
    steps(['a'.ord, '\n'.ord, 0x301]).should eq([{DisplayWidth::Placer::Step::Start, 1},
                                                 {DisplayWidth::Placer::Step::Start, 0},
                                                 {DisplayWidth::Placer::Step::Start, 0}])
  end

  it "joins nothing after reset" do
    placer = DisplayWidth::Placer.new
    placer.put('e')
    placer.reset
    placer.width.should eq(0)
    placer.put(0x301).should eq(DisplayWidth::Placer::Step::Start)
    placer.width.should eq(0)
  end

  it "takes the properties the caller looked up" do
    placer = DisplayWidth::Placer.new
    placer.put('\u{263A}', DisplayWidth.props('\u{263A}')).should eq(DisplayWidth::Placer::Step::Start)
    placer.put(0xFE0F_u32, DisplayWidth.props(0xFE0F_u32)).should eq(DisplayWidth::Placer::Step::Join)
    placer.width.should eq(2)
  end

  it "places code points without grapheme clusters under a policy without them" do
    steps([0x1F469, 0x200D, 0x1F4BB], DisplayWidth::Placer.new(LEGACY)).should eq([{DisplayWidth::Placer::Step::Start, 2},
                                                                                   {DisplayWidth::Placer::Step::Join, 2},
                                                                                   {DisplayWidth::Placer::Step::Start, 2}])
    steps([0x263A, 0xFE0F], DisplayWidth::Placer.new(LEGACY)).should eq([{DisplayWidth::Placer::Step::Start, 1},
                                                                         {DisplayWidth::Placer::Step::Join, 1}])
  end

  it "follows a new policy from the next code point on" do
    placer = DisplayWidth::Placer.new
    placer.policy = WIDE
    placer.put('±').should eq(DisplayWidth::Placer::Step::Start)
    placer.width.should eq(2)
  end

  it "steps past plain code points with plain! as put does" do
    placer = DisplayWidth::Placer.new
    placer.plain?.should be_true
    placer.plain!('1', 1)
    placer.width.should eq(1)
    placer.put(0xFE0F).should eq(DisplayWidth::Placer::Step::Join)
    placer.width.should eq(2)
    placer.put(0x0600)
    placer.plain?.should be_false
  end

  it "places text as DisplayWidth.of measures it" do
    ["", "hello", "漢字", "e\u{0301}x", "\u{1F469}\u{200D}\u{1F4BB} ok", "\u{1F1F3}\u{1F1F1}\u{1F1E7}",
     "\u{263A}\u{FE0F}\u{231A}\u{FE0E}", "\u{0301}a\u{200D}\u{1F4BB}", "a\u{7F}\u{85}b\nc\u{0301}",
     "\u{0E01}\u{0E33}\u{0915}\u{094D}\u{0937}"].each do |text|
      placed(text).should eq(DisplayWidth.of(text, RAW))
      placed(text, LEGACY).should eq(DisplayWidth.of(text, DisplayWidth::Policy.new(graphemes: false, escapes: false)))
    end
  end
end

describe "DisplayWidth.props" do
  it "looks up code points of every type" do
    DisplayWidth.props('a').should eq(DisplayWidth.props(0x61))
    DisplayWidth.props(0x61_u32).should eq(DisplayWidth.props(0x61))
    DisplayWidth.props(0x110000_u32).invalid?.should be_true
  end

  it "says which code points are plain, pictographic and invalid" do
    DisplayWidth.props('a').plain?.should be_true
    DisplayWidth.props(0x301).plain?.should be_false
    DisplayWidth.props(0x1F600).pictographic?.should be_true
    DisplayWidth.props(0x1F600).plain?.should be_false
    DisplayWidth.props(0x85).invalid?.should be_true
    DisplayWidth.props(0xFDD0).invalid?.should be_true
  end

  it "maps to cells through the policy" do
    policy = DisplayWidth::Policy.new
    policy.cells(DisplayWidth.props('a')).should eq(1)
    policy.cells(DisplayWidth.props(0x6F22)).should eq(2)
    policy.cells(DisplayWidth.props(0x301)).should eq(0)
    policy.cells(DisplayWidth.props('±')).should eq(1)
    WIDE.cells(DisplayWidth.props('±')).should eq(2)
  end
end
