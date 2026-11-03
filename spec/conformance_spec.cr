# spec/conformance_spec.cr
require "./spec_helper"

describe "Unicode conformance" do
  it "segments as GraphemeBreakTest.txt" do
    failures = [] of String
    File.each_line(File.join(DATA, "GraphemeBreakTest.txt")) do |line|
      tokens = line.partition('#')[0].split
      next if tokens.empty?
      segmenter = DisplayWidth::Segmenter.new
      (1...tokens.size).step(2) do |i|
        boundary = segmenter.step(DisplayWidth.props(tokens[i].to_i(16)))
        failures << line if i > 1 && boundary != (tokens[i - 1] == "÷")
      end
    end
    failures.should be_empty
  end

  it "gives every fully-qualified emoji and component one wide cluster" do
    failures = [] of String
    File.each_line(File.join(DATA, "emoji-qualified.txt")) do |line|
      next if line.starts_with?('#')
      text = hex(line)
      failures << line unless clusters(text).size == 1 && DisplayWidth.of(text) == 2
    end
    failures.should be_empty
  end

  it "gives emoji style two cells and text style one" do
    failures = [] of String
    File.each_line(File.join(DATA, "emoji-variation-sequences.txt")) do |line|
      fields = line.partition('#')[0].split(';').map(&.strip)
      next if fields.size < 2
      expected = fields[1] == "emoji style" ? 2 : 1
      failures << line unless DisplayWidth.of(hex(fields[0])) == expected
    end
    failures.should be_empty
  end
end
