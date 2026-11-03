# spec/stream_spec.cr
require "./spec_helper"

describe DisplayWidth::Stream do
  describe "#write" do
    it "yields clusters as the next one starts, and the last at flush" do
      widths { |write| write.call("ab漢") }.should eq([1, 1, 2])
    end

    it "joins a sequence split across chunks" do
      widths do |write, found|
        write.call(Bytes[0xE6])
        found.should be_empty
        write.call(Bytes[0xBC])
        write.call(Bytes[0xA2, 0x61])
        found.should eq([2])
      end.should eq([2, 1])
    end

    it "joins a cluster split across chunks" do
      widths do |write|
        write.call("e")
        write.call("\u{0301}")
        write.call("\u{1F469}")
        write.call("\u{200D}\u{1F4BB}")
      end.should eq([1, 2])
    end

    it "replaces a split ill-formed sequence by its maximal subpart" do
      widths do |write|
        write.call(Bytes[0xE2, 0x82])
        write.call(Bytes[0x41])
      end.should eq([1, 1])
      widths do |write|
        write.call(Bytes[0xF0])
        write.call(Bytes[0x80, 0x41])
      end.should eq([1, 1, 1])
    end

    it "replaces an unfinished sequence at flush" do
      widths { |write| write.call(Bytes[0xF0, 0x9F]) }.should eq([1])
    end

    it "takes code points one at a time" do
      widths do |write|
        write.call(0x1F469)
        write.call('\u{200D}')
        write.call(0x1F4BB_u32)
        write.call('a')
      end.should eq([2, 1])
    end

    it "replaces an unfinished sequence a code point interrupts" do
      widths do |write|
        write.call(Bytes[0xE2])
        write.call('a')
      end.should eq([1, 1])
    end

    it "starts afresh after flush" do
      stream = DisplayWidth::Stream.new
      stream.write("e") { }
      stream.flush { }
      widths(stream) { |write| write.call("\u{0301}") }.should eq([0])
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
