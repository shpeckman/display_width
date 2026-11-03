# src/display_width/segmenter.cr
require "./tables"

module DisplayWidth
  # :nodoc:
  # Extended grapheme cluster boundaries of UAX #29 revision 49 (Unicode 18.0.0), one code point at a time.
  #
  # The state is one byte: the last Grapheme_Cluster_Break value (bits 0-3, `START` before any), the
  # GB11 progress (bits 4-5: 1 after ExtPict Extend*, 2 after ExtPict Extend* ZWJ), an odd number of
  # regional indicators so far (bit 6, GB12 and GB13) and InCB=Linker InCB=Extend* last (bit 7, GB9c).
  struct Segmenter
    START  =   14_u8
    ODD    = 0x40_u8
    LINKER = 0x80_u8

    @state = START

    def reset : Nil
      @state = START
    end

    # Whether printable ASCII starts a cluster here: nothing, or Grapheme_Cluster_Break=Other, came last.
    @[AlwaysInline]
    def plain? : Bool
      prev = @state & 0xF
      prev == Break::Other.value || prev == START
    end

    # Moves past printable ASCII.
    @[AlwaysInline]
    def plain! : Nil
      @state = Break::Other.value
    end

    # Whether a boundary comes before a code point with *props*; moves past it either way.
    @[AlwaysInline]
    def step(props : Props) : Bool
      state = @state
      prev = state & 0xF
      if props.plain?
        @state = Break::Other.value
        return prev != Break::Prepend.value
      end
      cur = props.gcb
      emoji = (state >> 4) & 3
      boundary = (Segmenter.joins(prev) >> cur) & 1 == 0 &&
                 !(state & LINKER != 0 && props.incb == Conjunct::Consonant.value) &&
                 !(emoji == 2 && props.pictographic?) &&
                 !(state & ODD != 0 && prev == Break::RegionalIndicator.value && cur == Break::RegionalIndicator.value)
      emoji = if props.pictographic?
                1_u8
              elsif emoji == 1 && cur == Break::Extend.value
                1_u8
              elsif emoji == 1 && cur == Break::ZWJ.value
                2_u8
              else
                0_u8
              end
      odd = cur == Break::RegionalIndicator.value ? (state ^ ODD) & ODD : 0_u8
      linker = props.incb == Conjunct::Linker.value || (state & LINKER != 0 && props.incb == Conjunct::Extend.value)
      @state = cur | (emoji << 4) | odd | (linker ? LINKER : 0_u8)
      boundary
    end

    # Grapheme_Cluster_Break values (as bits) never broken from a preceding *prev*: rules GB3 to GB9b.
    @[AlwaysInline]
    def self.joins(prev : UInt8) : UInt16
      extending = bit(Break::Extend) | bit(Break::ZWJ) | bit(Break::SpacingMark)
      case prev
      when Break::CR.value
        bit(Break::LF)
      when Break::LF.value, Break::Control.value, START
        0_u16
      when Break::Prepend.value
        ((bit(Break::LVT) << 1) &- 1) & ~(bit(Break::CR) | bit(Break::LF) | bit(Break::Control))
      when Break::L.value
        extending | bit(Break::L) | bit(Break::V) | bit(Break::LV) | bit(Break::LVT)
      when Break::V.value, Break::LV.value
        extending | bit(Break::V) | bit(Break::T)
      when Break::T.value, Break::LVT.value
        extending | bit(Break::T)
      else
        extending
      end
    end

    @[AlwaysInline]
    private def self.bit(value : Break) : UInt16
      1_u16 << value.value
    end
  end
end
