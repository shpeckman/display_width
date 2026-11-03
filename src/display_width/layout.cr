# src/display_width/layout.cr
require "./engine"

module DisplayWidth
  private TAB = 0x09

  # Where `pad` places text in its cells.
  enum Align
    Left
    Right
    Center
  end

  # The longest start of *text* that takes at most *cells* cells, as `{bytes, width}`. It ends at a
  # cluster boundary, and takes in the zero-width clusters (escape sequences, controls) before the
  # first cluster that does not fit.
  #
  # ```
  # DisplayWidth.fit("漢字abc", 3) # => {3, 2}
  # DisplayWidth.fit("ab", 5)    # => {2, 2}
  # ```
  def self.fit(text : String, cells : Int32, policy : Policy = Policy.new) : {Int32, Int32}
    fit(text.to_slice, cells, policy)
  end

  # :ditto:
  def self.fit(bytes : Bytes, cells : Int32, policy : Policy = Policy.new) : {Int32, Int32}
    used = 0
    Engine.walk(bytes, policy) do |offset, _, width|
      return {offset, used} if used &+ width > cells
      used &+= width
    end
    {bytes.size, used}
  end

  # *text* cut to at most *cells* cells, ending in *tail* where it was cut. Text that fits comes back
  # as it is. The escape sequences after the cut are kept, after *tail*, so styles and hyperlinks end
  # as they would have; *tail* is left out when it does not fit by itself.
  #
  # ```
  # DisplayWidth.truncate("hello world", 8)               # => "hello w…"
  # DisplayWidth.truncate("漢字漢字", 6)                      # => "漢字…"
  # DisplayWidth.truncate("\e[1mhello world\e[0m", 6, "") # => "\e[1mhello \e[0m"
  # ```
  def self.truncate(text : String, cells : Int32, tail : String = "…", policy : Policy = Policy.new) : String
    return text if of(text, policy) <= cells
    String.build(text.bytesize) { |io| truncate(io, text, cells, tail, policy) }
  end

  # Writes *text* to *io*, cut as `truncate(text, cells, tail, policy)` cuts it.
  def self.truncate(io : IO, text : String, cells : Int32, tail : String = "…", policy : Policy = Policy.new) : Nil
    bytes = text.to_slice
    tail_width = of(tail, policy)
    tail, tail_width = "", 0 if tail_width > cells
    budget = cells &- tail_width
    cut = -1
    used = 0
    Engine.walk(bytes, policy) do |offset, _, width|
      cut = offset if cut < 0 && used &+ width > budget
      used &+= width
      break if used > cells
    end
    if used <= cells
      io.write(bytes)
      return
    end
    io.write(bytes[0, cut])
    io << tail
    return unless policy.escapes? && text.byte_index(Escape::ESC, cut)
    Engine.walk(bytes, policy) do |offset, size, _, escape|
      io.write(bytes[offset, size]) if escape && offset >= cut
    end
  end

  # *text* padded with spaces to *cells* cells, placed by *align*; `Align::Center` puts an odd space
  # on the right. Text that takes *cells* or more comes back as it is.
  #
  # ```
  # DisplayWidth.pad("漢", 4)           # => "漢  "
  # DisplayWidth.pad("漢", 4, :right)   # => "  漢"
  # DisplayWidth.pad("ab", 5, :center) # => " ab  "
  # ```
  def self.pad(text : String, cells : Int32, align : Align = Align::Left, policy : Policy = Policy.new) : String
    space = cells &- of(text, policy)
    return text if space <= 0
    String.build(text.bytesize &+ space) { |io| spaced(io, text, space, align) }
  end

  # Writes *text* to *io*, padded as `pad(text, cells, align, policy)` pads it.
  def self.pad(io : IO, text : String, cells : Int32, align : Align = Align::Left, policy : Policy = Policy.new) : Nil
    spaced(io, text, cells &- of(text, policy), align)
  end

  # Byte offset of the cluster that covers *column* (from 0) when *text* is drawn from column 0, or
  # the size of *text* when *column* is past its last cell. Zero-width clusters cover no column.
  #
  # ```
  # DisplayWidth.offset_at("a漢b", 2) # => 1
  # DisplayWidth.offset_at("a漢b", 3) # => 4
  # DisplayWidth.offset_at("a漢b", 9) # => 5
  # ```
  def self.offset_at(text : String, column : Int32, policy : Policy = Policy.new) : Int32
    offset_at(text.to_slice, column, policy)
  end

  # :ditto:
  def self.offset_at(bytes : Bytes, column : Int32, policy : Policy = Policy.new) : Int32
    reached = 0
    Engine.walk(bytes, policy) do |offset, _, width|
      reached &+= width
      return offset if column < reached
    end
    bytes.size
  end

  # The column the cursor reaches when one line of *text* is drawn from column *from*: a cluster
  # moves it by its width, a tab to the next multiple of *tab*. Other controls leave it in place.
  # Raises `ArgumentError` when *tab* is less than 1.
  #
  # ```
  # DisplayWidth.column("a\tb")         # => 9
  # DisplayWidth.column("\tx", from: 3) # => 9
  # DisplayWidth.column("a\tb", tab: 4) # => 5
  # ```
  def self.column(text : String, from : Int32 = 0, tab : Int32 = 8, policy : Policy = Policy.new) : Int32
    column(text.to_slice, from, tab, policy)
  end

  # :ditto:
  def self.column(bytes : Bytes, from : Int32 = 0, tab : Int32 = 8, policy : Policy = Policy.new) : Int32
    raise ArgumentError.new("tab stops must be at least 1 column apart, not #{tab}") if tab < 1
    at = from
    Engine.walk(bytes, policy) do |offset, _, width|
      if width == 0 && bytes.unsafe_fetch(offset) == TAB
        at = (at // tab + 1) * tab
      else
        at &+= width
      end
    end
    at
  end

  private def self.spaced(io : IO, text : String, space : Int32, align : Align) : Nil
    left = case align
           in .left?   then 0
           in .right?  then space
           in .center? then space // 2
           end
    left.times { io << ' ' }
    io << text
    (space &- left).times { io << ' ' }
  end
end
