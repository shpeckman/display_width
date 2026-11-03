# src/display_width/escape.cr
require "./utf8"

module DisplayWidth
  # :nodoc:
  # Escape sequences as kitty's parser (`kitty/vt-parser.c`) reads them: a code point at a time with
  # `step`, or the bytes that need no decoding at once with `scan`.
  #
  # ESC opens a sequence and the code point after it decides its kind: `[` a CSI, `]`, `P`, `X`, `^`
  # or `_` a string (OSC, DCS, SOS, PM, APC), one of `% ( ) * + - . / #` or space an escape that
  # takes one more code point; anything else ends it. A CSI runs over parameter and intermediate bytes
  # (U+0020 to U+003F) and ends with the next code point: a final byte, or anything else, which kitty
  # drops along with the sequence. kitty executes BEL, BS, HT, LF, VT, FF, CR, SO and SI inside a CSI
  # without ending it. A string runs to BEL or ST (ESC \).
  struct Escape
    BEL       = 0x07
    ESC       = 0x1B
    BACKSLASH = 0x5C

    BELS = 0x0707070707070707_u64
    ESCS = 0x1B1B1B1B1B1B1B1B_u64

    enum State : UInt8
      Ground
      Escape
      Intermediate
      CSI
      Payload
      PayloadEscape
    end

    @state = State::Ground

    @[AlwaysInline]
    def ground? : Bool
      @state.ground?
    end

    # Opens a sequence, on ESC.
    def start : Nil
      @state = State::Escape
    end

    def reset : Nil
      @state = State::Ground
    end

    # Whether *codepoint* belongs to the open sequence, which it may end; false for a control kitty
    # executes inside a CSI.
    @[AlwaysInline]
    def step(codepoint : Int32) : Bool
      @state = case @state
               in .ground?, .intermediate?
                 State::Ground
               in .escape?
                 Escape.after_escape(codepoint)
               in .csi?
                 return false if (codepoint &- BEL).to_u32! <= 8
                 (codepoint &- 0x20).to_u32! < 0x20 ? State::CSI : State::Ground
               in .payload?
                 case codepoint
                 when BEL then State::Ground
                 when ESC then State::PayloadEscape
                 else          State::Payload
                 end
               in .payload_escape?
                 case codepoint
                 when BACKSLASH, BEL then State::Ground
                 when ESC            then State::PayloadEscape
                 else                     State::Payload
                 end
               end
      true
    end

    # Steps the open sequence over the bytes at *ptr*, at most *avail*, until it ends or a byte needs
    # the code point path: a non-ASCII byte outside a string payload, or a control kitty executes
    # inside a CSI. Returns the bytes it took; string payloads and CSI parameters go whole.
    @[AlwaysInline]
    def scan(ptr : UInt8*, avail : Int32) : Int32
      n = 0
      until @state.ground? || n >= avail
        if @state.payload?
          n &+= Escape.payload(ptr + n, avail &- n)
          break if n >= avail
        elsif @state.csi?
          n &+= Escape.parameters(ptr + n, avail &- n)
          break if n >= avail
        end
        byte = ptr[n]
        break if byte >= 0x80 || !step(byte.to_i32)
        n &+= 1
      end
      n
    end

    # The state the code point after ESC opens.
    def self.after_escape(codepoint : Int32) : State
      case codepoint
      when 0x5B                                     then State::CSI
      when 0x5D, 0x50, 0x58, 0x5E, 0x5F             then State::Payload
      when 0x20, 0x23, 0x25, 0x28..0x2B, 0x2D..0x2F then State::Intermediate
      else                                               State::Ground
      end
    end

    # Number of parameter and intermediate bytes (U+0020 to U+003F) at the start of *ptr*, at most
    # *avail*: the part of a CSI that changes nothing.
    @[AlwaysInline]
    def self.parameters(ptr : UInt8*, avail : Int32) : Int32
      n = 0
      while n < avail && ptr[n] &- 0x20 < 0x20
        n &+= 1
      end
      n
    end

    # Number of bytes at the start of *ptr*, at most *avail*, before a BEL or an ESC: the part of a
    # string payload that changes nothing.
    @[AlwaysInline]
    def self.payload(ptr : UInt8*, avail : Int32) : Int32
      n = 0
      while n &+ 8 <= avail
        word = uninitialized UInt64
        (ptr + n).copy_to(pointerof(word).as(UInt8*), 8)
        bel = word ^ BELS
        esc = word ^ ESCS
        break unless (((bel &- UTF8::ONES) & ~bel) | ((esc &- UTF8::ONES) & ~esc)) & UTF8::HIGH_BITS == 0
        n &+= 8
      end
      while n < avail && (byte = ptr[n]) != BEL && byte != ESC
        n &+= 1
      end
      n
    end
  end
end
