# src/display_width/engine.cr
require "./tables"
require "./segmenter"
require "./utf8"
require "./policy"

module DisplayWidth
  # :nodoc:
  # kitty's algorithm for splitting text into cells, holding back the cluster still open.
  #
  # A C0 control is a cluster of its own. A cluster absorbs invalid code points (DEL, C1, surrogates,
  # noncharacters) without stepping the segmenter, as kitty discards them. Zero-width code points with
  # no cell to join form a zero-width cluster, as kitty discards those too.
  struct Engine
    VS15 = 0xFE0E
    VS16 = 0xFE0F

    enum Kind : UInt8
      None
      Cell
      Orphan
      Control
    end

    # Cells of all clusters so far, the open one included.
    getter total = 0
    # Cells of the open cluster.
    getter width = 0
    @kind = Kind::None
    @start = 0
    @base = false
    @segmenter = Segmenter.new
    @policy : Policy

    def initialize(@policy : Policy)
    end

    # Feeds the code point at *offset*; yields the offset, size and width of the cluster it finishes.
    @[AlwaysInline]
    def put(codepoint : Int32, offset : Int32, & : Int32, Int32, Int32 ->) : Nil
      start, width, open = @start, @width, !@kind.none?
      return unless push(codepoint)
      yield start, offset &- start, width if open
      @start = offset
    end

    # Feeds *size* UTF-8 bytes at *ptr*, yielding as `put`. Returns the bytes consumed: all of them,
    # unless not *final* and they end inside a well-formed sequence.
    def feed(ptr : UInt8*, size : Int32, final : Bool, & : Int32, Int32, Int32 ->) : Int32
      i = 0
      while i < size
        if ptr[i] &- 0x20 < 0x5F && @segmenter.plain?
          n = UTF8.ascii(ptr + i, size &- i)
          yield @start, i &- @start, @width unless @kind.none?
          last = i &+ n &- 1
          while i < last
            yield i, 1, 1
            i &+= 1
          end
          @kind = Kind::Cell
          @width = 1
          @total &+= n
          @base = DisplayWidth.props(ptr[last].to_i32).emoji_base?
          @segmenter.plain!
          @start = last
          i = last &+ 1
          next
        end
        codepoint, length = UTF8.decode(ptr + i, size &- i)
        if length < 0
          return i unless final
          length = -length
        end
        put(codepoint, i) { |o, s, w| yield o, s, w }
        i &+= length
      end
      size
    end

    # Yields the open cluster, ending at *offset*, and starts afresh.
    def finish(offset : Int32, & : Int32, Int32, Int32 ->) : Nil
      yield @start, offset &- @start, @width unless @kind.none?
      @kind = Kind::None
      @width = 0
      @start = offset
      @segmenter.reset
    end

    # Feeds *codepoint*; whether it starts a cluster, finishing the open one.
    @[AlwaysInline]
    private def push(codepoint : Int32) : Bool
      if codepoint.to_u32! < 0x20
        @segmenter.reset
        open(Kind::Control, 0)
        return true
      end
      props = DisplayWidth.props(codepoint)
      if props.invalid?
        return false if @kind.cell? || @kind.orphan?
        open(Kind::Orphan, 0)
        return true
      end
      boundary = !@policy.graphemes? || @segmenter.step(props)
      width = @policy.cells(props)
      if @kind.cell?
        if !boundary || width == 0
          join(codepoint, props)
          return false
        end
      elsif width == 0
        return false if @kind.orphan?
        open(Kind::Orphan, 0)
        return true
      end
      open(Kind::Cell, width)
      @base = props.emoji_base?
      true
    end

    @[AlwaysInline]
    private def open(kind : Kind, width : Int32) : Nil
      @kind = kind
      @width = width
      @total &+= width
    end

    @[AlwaysInline]
    private def join(codepoint : Int32, props : Props) : Nil
      if @policy.graphemes?
        if codepoint == VS16
          resize(1) if @width == 1 && @base
        elsif codepoint == VS15
          resize(-1) if @width == 2 && @base
        elsif @width == 1 && props.widens?
          resize(1)
        end
      end
      @base = props.emoji_base?
    end

    @[AlwaysInline]
    private def resize(by : Int32) : Nil
      @width &+= by
      @total &+= by
    end
  end
end
