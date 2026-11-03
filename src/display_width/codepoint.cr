# src/display_width/codepoint.cr
module DisplayWidth
  # A code point: a `Char`, or its value as an `Int32` or `UInt32`. Values outside the code space
  # (and surrogates) are invalid code points and take no cells.
  alias Codepoint = Char | Int32 | UInt32

  # :nodoc:
  @[AlwaysInline]
  def self.ord(codepoint : Codepoint) : Int32
    case codepoint
    in Char   then codepoint.ord
    in Int32  then codepoint
    in UInt32 then codepoint > 0x10FFFF ? -1 : codepoint.to_i32!
    end
  end
end
