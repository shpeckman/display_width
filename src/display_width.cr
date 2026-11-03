# src/display_width.cr
require "./display_width/codepoint"
require "./display_width/engine"
require "./display_width/stream"

# Terminal cells taken by code points and text, from the Unicode `UNICODE_VERSION` tables and
# kitty's algorithm for splitting text into cells.
#
# ```
# DisplayWidth.of('漢')                             # => 2
# DisplayWidth.of("e\u{0301}")                     # => 1
# DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB} ok") # => 5
# DisplayWidth.each_cluster("a\u{1F44D}\u{1F3FD}") { |offset, size, width| p({offset, size, width}) }
# # {0, 1, 1}
# # {1, 8, 2}
# ```
module DisplayWidth
  # Cells *codepoint* takes on its own: 0, 1 or 2. C0 controls and invalid code points take 0.
  def self.of(codepoint : Codepoint, policy : Policy = Policy.new) : Int32
    cp = ord(codepoint)
    return 0 if cp.to_u32! < 0x20
    props = props(cp)
    props.invalid? ? 0 : policy.cells(props)
  end

  # Cells *text* takes, the sum of its clusters' widths. Ill-formed UTF-8 counts as U+FFFD.
  def self.of(text : String, policy : Policy = Policy.new) : Int32
    of(text.to_slice, policy)
  end

  # :ditto:
  def self.of(bytes : Bytes, policy : Policy = Policy.new) : Int32
    engine = Engine.new(policy)
    engine.feed(bytes.to_unsafe, bytes.size, true) { }
    engine.total
  end

  # Cells a sequence of code points takes, the sum of its clusters' widths.
  def self.of(codepoints : Enumerable(Char) | Enumerable(Int32) | Enumerable(UInt32), policy : Policy = Policy.new) : Int32
    engine = Engine.new(policy)
    codepoints.each { |codepoint| engine.put(ord(codepoint), 0) { } }
    engine.total
  end

  # Yields the byte offset, byte size and width (0, 1 or 2) of each cluster of *text*: the code points
  # a terminal puts in one cell, or a C0 control, or zero-width code points with no cell to join.
  # The clusters cover *text* without gaps.
  def self.each_cluster(text : String, policy : Policy = Policy.new, & : Int32, Int32, Int32 ->) : Nil
    each_cluster(text.to_slice, policy) { |offset, size, width| yield offset, size, width }
  end

  # :ditto:
  def self.each_cluster(bytes : Bytes, policy : Policy = Policy.new, & : Int32, Int32, Int32 ->) : Nil
    engine = Engine.new(policy)
    engine.feed(bytes.to_unsafe, bytes.size, true) { |offset, size, width| yield offset, size, width }
    engine.finish(bytes.size) { |offset, size, width| yield offset, size, width }
  end

  # Yields the index, length and width of each cluster of *codepoints*, counted in code points.
  def self.each_cluster(codepoints : Enumerable(Char) | Enumerable(Int32) | Enumerable(UInt32), policy : Policy = Policy.new, & : Int32, Int32, Int32 ->) : Nil
    engine = Engine.new(policy)
    index = 0
    codepoints.each do |codepoint|
      engine.put(ord(codepoint), index) { |offset, size, width| yield offset, size, width }
      index &+= 1
    end
    engine.finish(index) { |offset, size, width| yield offset, size, width }
  end
end
