# src/display_width/policy.cr
require "./props"

module DisplayWidth
  # How text maps to cells, to match the terminal it is drawn on.
  #
  # - *ambiguous*: cells of an East Asian Ambiguous code point, 1 or 2 (as CJK terminals draw them).
  # - *graphemes*: `true` places grapheme clusters in cells as kitty's algorithm does (mode 2027
  #   terminals); `false` places code points as terminals without grapheme support do: every code
  #   point with a width starts a cell, and variation selectors change nothing.
  #
  # ```
  # DisplayWidth.of("±", DisplayWidth::Policy.new(ambiguous: 2))                              # => 2
  # DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB}", DisplayWidth::Policy.new(graphemes: false)) # => 4
  # ```
  struct Policy
    getter ambiguous : Int32
    getter? graphemes : Bool
    @classes : UInt8

    def initialize(@ambiguous : Int32 = 1, @graphemes : Bool = true)
      unless @ambiguous == 1 || @ambiguous == 2
        raise ArgumentError.new("ambiguous width must be 1 or 2, not #{@ambiguous}")
      end
      @classes = (0b10_01_00 | (@ambiguous << 6)).to_u8!
    end

    # :nodoc:
    @[AlwaysInline]
    def cells(props : Props) : Int32
      ((@classes >> (props.cells << 1)) & 3).to_i32!
    end
  end
end
