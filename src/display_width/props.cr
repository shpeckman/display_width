# src/display_width/props.cr
module DisplayWidth
  # :nodoc:
  enum Break : UInt8
    Other
    CR
    LF
    Control
    Extend
    ZWJ
    RegionalIndicator
    Prepend
    SpacingMark
    L
    V
    T
    LV
    LVT
  end

  # :nodoc:
  enum Conjunct : UInt8
    None
    Linker
    Consonant
    Extend
  end

  # :nodoc:
  enum Cells : UInt8
    Zero
    One
    Two
    Ambiguous
  end

  # :nodoc:
  # Properties of one code point: Grapheme_Cluster_Break (bits 0-3), Indic_Conjunct_Break (4-5),
  # Extended_Pictographic (6), emoji presentation base (7), `Cells` class (8-9) and invalid (10).
  record Props, bits : UInt16 do
    def self.pack(gcb : Break, incb : Conjunct, pictographic : Bool, emoji_base : Bool, cells : Cells, invalid : Bool) : self
      new(gcb.value.to_u16 | (incb.value.to_u16 << 4) | (pictographic ? 0x40_u16 : 0_u16) |
          (emoji_base ? 0x80_u16 : 0_u16) | (cells.value.to_u16 << 8) | (invalid ? 0x400_u16 : 0_u16))
    end

    @[AlwaysInline]
    def gcb : UInt8
      (bits & 0xF).to_u8!
    end

    @[AlwaysInline]
    def incb : UInt8
      ((bits >> 4) & 3).to_u8!
    end

    @[AlwaysInline]
    def pictographic? : Bool
      bits & 0x40 != 0
    end

    @[AlwaysInline]
    def emoji_base? : Bool
      bits & 0x80 != 0
    end

    @[AlwaysInline]
    def cells : UInt8
      ((bits >> 8) & 3).to_u8!
    end

    @[AlwaysInline]
    def invalid? : Bool
      bits & 0x400 != 0
    end

    # Grapheme_Cluster_Break=Other, Indic_Conjunct_Break=None and not Extended_Pictographic: such a
    # code point starts a cluster unless a Prepend came before it, and leaves no segmenter state.
    @[AlwaysInline]
    def plain? : Bool
      bits & 0x7F == 0
    end

    # A SpacingMark with a width of its own widens the narrow cell it joins (Thai and Lao SARA AM).
    @[AlwaysInline]
    def widens? : Bool
      gcb == Break::SpacingMark.value && (cells == Cells::One.value || cells == Cells::Two.value)
    end
  end
end
