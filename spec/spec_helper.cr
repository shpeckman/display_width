# spec/spec_helper.cr
require "spec"
require "../src/display_width"

DATA = File.join(__DIR__, "data")

LEGACY = DisplayWidth::Policy.new(graphemes: false)
WIDE   = DisplayWidth::Policy.new(ambiguous: 2)
RAW    = DisplayWidth::Policy.new(escapes: false)

def clusters(text : String | Bytes, policy = DisplayWidth::Policy.new) : Array({Int32, Int32, Int32})
  found = [] of {Int32, Int32, Int32}
  DisplayWidth.each_cluster(text, policy) { |offset, size, width| found << {offset, size, width} }
  found
end

def hex(sequence : String) : String
  String.build { |io| sequence.split.each { |code| io << code.to_i(16).chr } }
end

def widths(stream : DisplayWidth::Stream, & : DisplayWidth::Stream, Array(Int32) ->) : Array(Int32)
  found = [] of Int32
  yield stream, found
  stream.flush { |width| found << width }
  found
end
