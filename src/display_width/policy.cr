# src/display_width/policy.cr
require "./props"

module DisplayWidth
  # How text maps to cells, to match the terminal it is drawn on.
  #
  # - *ambiguous*: cells of an East Asian Ambiguous code point, 1 or 2 (as CJK terminals draw them).
  # - *graphemes*: `true` places grapheme clusters in cells as kitty's algorithm does (mode 2027
  #   terminals); `false` places code points as terminals without grapheme support do: every code
  #   point with a width starts a cell, and variation selectors change nothing.
  # - *escapes*: `true` reads escape sequences (SGR, OSC 8 hyperlinks, ...) as kitty's parser does,
  #   taking no cells; `false` makes ESC a plain C0 control and what follows it text.
  #
  # ```
  # DisplayWidth.of("±", DisplayWidth::Policy.new(ambiguous: 2))                              # => 2
  # DisplayWidth.of("\u{1F469}\u{200D}\u{1F4BB}", DisplayWidth::Policy.new(graphemes: false)) # => 4
  # DisplayWidth.of("\e[1mbold\e[0m", DisplayWidth::Policy.new(escapes: false))               # => 10
  # ```
  struct Policy
    getter ambiguous : Int32
    getter? graphemes : Bool
    getter? escapes : Bool
    @classes : UInt8

    def initialize(@ambiguous : Int32 = 1, @graphemes : Bool = true, @escapes : Bool = true)
      unless @ambiguous == 1 || @ambiguous == 2
        raise ArgumentError.new("ambiguous width must be 1 or 2, not #{@ambiguous}")
      end
      @classes = (0b10_01_00 | (@ambiguous << 6)).to_u8!
    end

    # Cells a code point with *props* takes on its own: 0, 1 or 2. Controls and invalid code points
    # are the caller's: `DisplayWidth.of` gives them 0.
    @[AlwaysInline]
    def cells(props : Props) : Int32
      ((@classes >> (props.cells << 1)) & 3).to_i32!
    end
  end
end
