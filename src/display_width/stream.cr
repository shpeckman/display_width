# src/display_width/stream.cr
require "./codepoint"
require "./engine"

module DisplayWidth
  # Measures text that arrives in pieces: UTF-8 chunks split anywhere, or code points one at a time.
  # Escape sequences can be split too.
  #
  # `write` yields the width of each cluster once it is finished, which is when the next one starts
  # or at `flush`. `advance` returns how far the text moved the cursor, as a terminal moves it: a
  # cluster's cells as it starts, then +1 or -1 when a variation selector or a spacing mark resizes it.
  #
  # ```
  # stream = DisplayWidth::Stream.new
  # stream.write(Bytes[0xE6]) { |width| p width }             # nothing finished yet
  # stream.write(Bytes[0xBC, 0xA2, 0x61]) { |width| p width } # prints 2 ("漢")
  # stream.flush { |width| p width }                          # prints 1 ("a")
  #
  # cursor = DisplayWidth::Stream.new
  # cursor.advance('\u{231A}') # => 2
  # cursor.advance('\u{FE0E}') # => -1
  # ```
  class Stream
    @engine : Engine
    @carry = StaticArray(UInt8, 4).new(0_u8)
    @carried = 0

    def initialize(policy : Policy = Policy.new)
      @engine = Engine.new(policy)
    end

    # Feeds UTF-8 *bytes*; yields the width of each cluster they finish.
    def write(bytes : Bytes, & : Int32 ->) : Nil
      consume(bytes) { |width| yield width }
    end

    # :ditto:
    def write(text : String, & : Int32 ->) : Nil
      consume(text.to_slice) { |width| yield width }
    end

    # Feeds one code point; yields the width of the cluster it finishes.
    def write(codepoint : Codepoint, & : Int32 ->) : Nil
      settle { |width| yield width }
      @engine.put(DisplayWidth.ord(codepoint), 0) { |_, _, width| yield width }
    end

    # Feeds UTF-8 *bytes*; returns the cells they moved the cursor by.
    def advance(bytes : Bytes) : Int32
      total = @engine.total
      consume(bytes) { }
      @engine.total &- total
    end

    # :ditto:
    def advance(text : String) : Int32
      advance(text.to_slice)
    end

    # Feeds one code point; returns the cells it moved the cursor by.
    def advance(codepoint : Codepoint) : Int32
      total = @engine.total
      write(codepoint) { }
      @engine.total &- total
    end

    # Ends the text: an unfinished UTF-8 sequence becomes U+FFFD, and the open cluster is yielded.
    # What follows starts with no cell to join, outside any escape sequence.
    def flush(& : Int32 ->) : Nil
      settle { |width| yield width }
      @engine.finish(0) { |_, _, width| yield width }
    end

    private def settle(& : Int32 ->) : Nil
      return if @carried == 0
      @carried = 0
      @engine.put(UTF8::REPLACEMENT, 0) { |_, _, width| yield width }
    end

    private def consume(bytes : Bytes, & : Int32 ->) : Nil
      i = 0
      while @carried > 0 && i < bytes.size
        @carry[@carried] = bytes[i]
        @carried += 1
        i += 1
        codepoint, length = UTF8.decode(@carry.to_unsafe, @carried)
        next if length < 0
        i -= @carried - length
        @carried = 0
        @engine.put(codepoint, 0) { |_, _, width| yield width }
      end
      return if @carried > 0
      ptr = bytes.to_unsafe + i
      size = bytes.size - i
      used = @engine.feed(ptr, size, false) { |_, _, width| yield width }
      (ptr + used).copy_to(@carry.to_unsafe, size - used)
      @carried = size - used
    end
  end
end
