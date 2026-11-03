# src/display_width/engine.cr
require "./placer"
require "./escape"
require "./utf8"

module DisplayWidth
  # :nodoc:
  # kitty's algorithm for splitting text into cells over `Placer`, holding back the cluster still
  # open: a C0 control is a cluster of its own, invalid code points join the open cluster, and
  # zero-width code points with no cell to join form a zero-width cluster.
  #
  # Escape sequences leave the open cluster and the segmenter alone: kitty rebuilds its segmentation
  # state from the cell before the cursor after each one (`init_segmentation_state` in `screen.c`).
  # They are held back from `@held` on. When the next code point starts a cluster, they become a
  # zero-width cluster of their own; when it joins the open cluster, they join it too. While `@held`
  # is `NOTHING`, no sequence is open or held back, and code points take the fast path.
  #
  # Clusters are yielded as offset, size, width and whether they are escape sequences.
  struct Engine
    # `@held` when no escape sequence is open or held back.
    NOTHING = -1
    # `@held` when a sequence is open but none of it is held back: a control inside a CSI took its
    # start into a cluster.
    OPEN = -2

    # Cells of the clusters closed so far.
    @done = 0
    @start = 0
    @held = NOTHING
    @placer : Placer
    @escape = Escape.new

    def initialize(policy : Policy)
      @placer = Placer.new(policy)
    end

    # Cells of all clusters so far, the open one included.
    def total : Int32
      @done &+ @placer.width
    end

    # Yields every cluster of *bytes*.
    def self.walk(bytes : Bytes, policy : Policy, & : Int32, Int32, Int32, Bool ->) : Nil
      engine = new(policy)
      engine.feed(bytes.to_unsafe, bytes.size, true) { |offset, size, width, escape| yield offset, size, width, escape }
      engine.finish(bytes.size) { |offset, size, width, escape| yield offset, size, width, escape }
    end

    # Feeds the code point at *offset*; yields the clusters it finishes.
    @[AlwaysInline]
    def put(codepoint : Int32, offset : Int32, & : Int32, Int32, Int32, Bool ->) : Nil
      if @held == NOTHING
        plain(codepoint, offset) { |o, s, w, e| yield o, s, w, e }
      else
        escaped(codepoint, offset) { |o, s, w, e| yield o, s, w, e }
      end
    end

    # Feeds *size* UTF-8 bytes at *ptr*, yielding as `put`. Returns the bytes consumed: all of them,
    # unless not *final* and they end inside a well-formed sequence.
    #
    # The inner loop runs while no escape sequence is open or held back; the outer one scans escape
    # sequences byte by byte, and feeds what `Escape#scan` leaves a code point at a time.
    def feed(ptr : UInt8*, size : Int32, final : Bool, & : Int32, Int32, Int32, Bool ->) : Int32
      i = 0
      while i < size
        if @held == NOTHING
          while i < size
            if ptr[i] &- 0x20 < 0x5F && @placer.plain?
              n = UTF8.ascii(ptr + i, size &- i)
              yield @start, i &- @start, @placer.width, false if @placer.open?
              @done &+= @placer.width &+ n &- 1
              last = i &+ n &- 1
              while i < last
                yield i, 1, 1, false
                i &+= 1
              end
              @placer.plain!(ptr[last].to_i32, 1)
              @start = last
              i = last &+ 1
              next
            end
            codepoint, length = UTF8.decode(ptr + i, size &- i)
            if length < 0
              return i unless final
              length = -length
            end
            plain(codepoint, i) { |o, s, w, e| yield o, s, w, e }
            i &+= length
            break unless @held == NOTHING
          end
          next
        end
        n = @escape.scan(ptr + i, size &- i)
        if n > 0
          @held = i if @held == OPEN
          i &+= n
          next
        end
        codepoint, length = UTF8.decode(ptr + i, size &- i)
        if length < 0
          return i unless final
          length = -length
        end
        escaped(codepoint, i) { |o, s, w, e| yield o, s, w, e }
        i &+= length
      end
      size
    end

    # Yields the open cluster and the escape sequences held back after it, ending at *offset*, and
    # starts afresh.
    def finish(offset : Int32, & : Int32, Int32, Int32, Bool ->) : Nil
      release(@start, @placer.width, @placer.open?, offset) { |o, s, w, e| yield o, s, w, e }
      @done &+= @placer.width
      @placer.reset
      @start = offset
      @escape.reset
    end

    # Feeds the code point at *offset* while no escape sequence is open or held back.
    @[AlwaysInline]
    private def plain(codepoint : Int32, offset : Int32, & : Int32, Int32, Int32, Bool ->) : Nil
      start, width, open = @start, @placer.width, @placer.open?
      return unless push(codepoint, offset).start?
      @done &+= width
      yield start, offset &- start, width, false if open
      @start = offset
    end

    # Feeds the code point at *offset* while an escape sequence is open or held back.
    private def escaped(codepoint : Int32, offset : Int32, & : Int32, Int32, Int32, Bool ->) : Nil
      if !@escape.ground? && @escape.step(codepoint)
        @held = offset if @held == OPEN
        return
      end
      start, width, open = @start, @placer.width, @placer.open?
      case push(codepoint, offset)
      in .skip?
        return
      in .join?
        @held = NOTHING
        return
      in .start?
      end
      @done &+= width
      release(start, width, open, offset) { |o, s, w, e| yield o, s, w, e }
      @held = OPEN unless @escape.ground?
      @start = offset
    end

    # Yields the cluster that was open, if *open*, and the escape sequences held back after it, all
    # ending at *offset*.
    @[AlwaysInline]
    private def release(start : Int32, width : Int32, open : Bool, offset : Int32, & : Int32, Int32, Int32, Bool ->) : Nil
      held = @held
      if held < 0
        yield start, offset &- start, width, false if open
      else
        yield start, held &- start, width, false if open
        yield held, offset &- held, 0, true
      end
      @held = NOTHING
    end

    # Feeds *codepoint*, at *offset*, outside escape sequences.
    @[AlwaysInline]
    private def push(codepoint : Int32, offset : Int32) : Placer::Step
      if codepoint == Escape::ESC && @placer.policy.escapes?
        @escape.start
        @held = offset if @held < 0
        return Placer::Step::Skip
      end
      @placer.put(codepoint)
    end
  end
end
