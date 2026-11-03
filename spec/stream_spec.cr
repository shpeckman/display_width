# spec/stream_spec.cr
require "./spec_helper"

describe DisplayWidth::Stream do
  describe "#write" do
    it "yields clusters as the next one starts, and the last at flush" do
      widths(DisplayWidth::Stream.new) { |stream, found| stream.write("ab漢") { |w| found << w } }.should eq([1, 1, 2])
    end

    it "joins a sequence split across chunks" do
      widths(DisplayWidth::Stream.new) do |stream, found|
        stream.write(Bytes[0xE6]) { |w| found << w }
        found.should be_empty
        stream.write(Bytes[0xBC]) { |w| found << w }
        stream.write(Bytes[0xA2, 0x61]) { |w| found << w }
        found.should eq([2])
      end.should eq([2, 1])
    end

    it "joins a cluster split across chunks" do
      widths(DisplayWidth::Stream.new) do |stream, found|
        stream.write("e") { |w| found << w }
        stream.write("\u{0301}") { |w| found << w }
        stream.write("\u{1F469}") { |w| found << w }
        stream.write("\u{200D}\u{1F4BB}") { |w| found << w }
      end.should eq([1, 2])
    end

    it "replaces a split ill-formed sequence by its maximal subpart" do
      widths(DisplayWidth::Stream.new) do |stream, found|
        stream.write(Bytes[0xE2, 0x82]) { |w| found << w }
        stream.write(Bytes[0x41]) { |w| found << w }
      end.should eq([1, 1])
      widths(DisplayWidth::Stream.new) do |stream, found|
        stream.write(Bytes[0xF0]) { |w| found << w }
        stream.write(Bytes[0x80, 0x41]) { |w| found << w }
      end.should eq([1, 1, 1])
    end

    it "replaces an unfinished sequence at flush" do
      widths(DisplayWidth::Stream.new) { |stream, found| stream.write(Bytes[0xF0, 0x9F]) { |w| found << w } }.should eq([1])
    end

    it "takes code points one at a time" do
      widths(DisplayWidth::Stream.new) do |stream, found|
        stream.write(0x1F469) { |w| found << w }
        stream.write('\u{200D}') { |w| found << w }
        stream.write(0x1F4BB_u32) { |w| found << w }
        stream.write('a') { |w| found << w }
      end.should eq([2, 1])
    end

    it "replaces an unfinished sequence a code point interrupts" do
      widths(DisplayWidth::Stream.new) do |stream, found|
        stream.write(Bytes[0xE2]) { |w| found << w }
        stream.write('a') { |w| found << w }
      end.should eq([1, 1])
    end

    it "starts afresh after flush" do
      stream = DisplayWidth::Stream.new
      stream.write("e") { }
      stream.flush { }
      widths(stream) { |s, found| s.write("\u{0301}") { |w| found << w } }.should eq([0])
    end
  end

  describe "#advance" do
    it "moves the cursor as a terminal does" do
      stream = DisplayWidth::Stream.new
      stream.advance('e').should eq(1)
      stream.advance('\u{0301}').should eq(0)
      stream.advance('\u{263A}').should eq(1)
      stream.advance('\u{FE0F}').should eq(1)
      stream.advance('\u{231A}').should eq(2)
      stream.advance('\u{FE0E}').should eq(-1)
      stream.advance('\u{0E01}').should eq(1)
      stream.advance('\u{0E33}').should eq(1)
    end

    it "sums a chunk" do
      DisplayWidth::Stream.new.advance("\u{1F469}\u{200D}\u{1F4BB} ok").should eq(5)
    end

    it "counts a split sequence once it completes" do
      stream = DisplayWidth::Stream.new
      stream.advance(Bytes[0xF0, 0x9F]).should eq(0)
      stream.advance(Bytes[0x98, 0x80]).should eq(2)
    end

    it "follows the policy" do
      DisplayWidth::Stream.new(LEGACY).advance("\u{1F469}\u{200D}\u{1F4BB}").should eq(4)
      DisplayWidth::Stream.new(WIDE).advance("±").should eq(2)
    end
  end
end
