# src/display_width/placer.cr
require "./codepoint"
require "./tables"
require "./segmenter"
require "./policy"

module DisplayWidth
  # kitty's placement of code points in cells, one code point at a time, for programs that draw text
  # as it arrives, such as terminal emulators. `DisplayWidth.of` and `DisplayWidth.each_cluster` place
  # text with it.
  #
  # `put` says what a code point did: `Step::Start` opened a cluster of `width` cells, `Step::Join`
  # added it to the open cluster (VS16, VS15 and Thai and Lao SARA AM change its `width`) and
  # `Step::Skip` discarded it. A cluster of 0 cells is no cell: a C0 control, or zero-width code
  # points with no cell to join, which kitty discards.
  #
  # The placer knows nothing of escape sequences: kitty keeps the open cell across them. `reset` it
  # where nothing may join the open cell any more.
  #
  # ```
  # placer = DisplayWidth::Placer.new
  # placer.put('e')        # => Start, placer.width == 1
  # placer.put(0x301)      # => Join, placer.width == 1
  # placer.put('\u{2764}') # => Start, placer.width == 1
  # placer.put(0xFE0F)     # => Join, placer.width == 2
  # placer.put(0x301)      # => Join, placer.width == 2
  # placer.reset
  # placer.put(0x301) # => Start, placer.width == 0
  # ```
  struct Placer
    # What a code point did.
    enum Step : UInt8
      # Discarded: an invalid code point (DEL, C1, a surrogate, a noncharacter or a value outside the
      # code space) while a cluster is open, which stays open.
      Skip
      # Joined the open cluster.
      Join
      # Opened a cluster, closing the one that was open.
      Start
    end

    private VS15 = 0xFE0E
    private VS16 = 0xFE0F

    private enum Kind : UInt8
      None
      Cell
      Orphan
      Control
    end

    # Cells of the open cluster: 1 or 2 for a cell; 0 for none, a C0 control, or zero-width and
    # invalid code points with no cell to join.
    getter width = 0
    # How code points map to cells. A new policy applies from the next code point on.
    property policy : Policy
    @kind = Kind::None
    # The last code point of the open cluster: VS15 and VS16 look at it.
    @last = 0
    @segmenter = Segmenter.new

    def initialize(@policy : Policy = Policy.new)
    end

    # :nodoc:
    # Whether a cluster is open: a code point came since `new` or `reset`.
    @[AlwaysInline]
    def open? : Bool
      !@kind.none?
    end

    # Places *codepoint*.
    @[AlwaysInline]
    def put(codepoint : Codepoint) : Step
      cp = DisplayWidth.ord(codepoint)
      cp.to_u32! < 0x20 ? control : step(cp, DisplayWidth.props(cp))
    end

    # Places *codepoint*, whose properties (`DisplayWidth.props`) the caller has at hand.
    @[AlwaysInline]
    def put(codepoint : Codepoint, props : Props) : Step
      cp = DisplayWidth.ord(codepoint)
      cp.to_u32! < 0x20 ? control : step(cp, props)
    end

    # Closes the open cluster and starts segmentation afresh: what comes next joins nothing.
    @[AlwaysInline]
    def reset : Nil
      @kind = Kind::None
      @width = 0
      @segmenter.reset
    end

    # Whether a code point whose `Props#plain?` holds starts a cell here when it has a width, so that
    # `plain!` may stand in for `put`: unless a Prepend came last.
    @[AlwaysInline]
    def plain? : Bool
      @segmenter.plain?
    end

    # Moves past *codepoint* while `plain?`: one whose `Props#plain?` holds and that takes *width*
    # cells (1 or 2) under `policy`. Does what `put` does then, without its checks.
    @[AlwaysInline]
    def plain!(codepoint : Codepoint, width : Int32) : Nil
      @kind = Kind::Cell
      @width = width
      @last = DisplayWidth.ord(codepoint)
      @segmenter.plain!
    end

    @[AlwaysInline]
    private def control : Step
      @segmenter.reset
      open(Kind::Control, 0)
      Step::Start
    end

    @[AlwaysInline]
    private def step(codepoint : Int32, props : Props) : Step
      if props.invalid?
        return Step::Skip if @kind.cell? || @kind.orphan?
        open(Kind::Orphan, 0)
        return Step::Start
      end
      boundary = !@policy.graphemes? || @segmenter.step(props)
      width = @policy.cells(props)
      if @kind.cell?
        if !boundary || width == 0
          join(codepoint, props)
          return Step::Join
        end
      elsif width == 0
        return Step::Join if @kind.orphan?
        open(Kind::Orphan, 0)
        return Step::Start
      end
      open(Kind::Cell, width)
      @last = codepoint
      Step::Start
    end

    @[AlwaysInline]
    private def open(kind : Kind, width : Int32) : Nil
      @kind = kind
      @width = width
    end

    @[AlwaysInline]
    private def join(codepoint : Int32, props : Props) : Nil
      if @policy.graphemes?
        if codepoint == VS16
          @width = 2 if @width == 1 && DisplayWidth.props(@last).emoji_base?
        elsif codepoint == VS15
          @width = 1 if @width == 2 && DisplayWidth.props(@last).emoji_base?
        elsif @width == 1 && props.widens?
          @width = 2
        end
      end
      @last = codepoint
    end
  end
end
