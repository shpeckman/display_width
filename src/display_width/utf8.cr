# src/display_width/utf8.cr
module DisplayWidth
  # :nodoc:
  module UTF8
    REPLACEMENT = 0xFFFD

    PRINTABLE_LOW  = 0x2020202020202020_u64
    PRINTABLE_HIGH = 0x7F7F7F7F7F7F7F7F_u64
    ONES           = 0x0101010101010101_u64
    HIGH_BITS      = 0x8080808080808080_u64

    # Decodes the code point at *ptr* from *avail* (> 0) bytes: `{code point, size}`. An ill-formed
    # sequence decodes to `{REPLACEMENT, size of its maximal subpart}`; a well-formed start cut off
    # by *avail* to `{REPLACEMENT, -size}`.
    @[AlwaysInline]
    def self.decode(ptr : UInt8*, avail : Int32) : {Int32, Int32}
      lead = ptr[0].to_i32
      return {lead, 1} if lead < 0x80
      if lead < 0xE0
        if lead >= 0xC2 && avail >= 2 && ptr[1] & 0xC0 == 0x80
          return {((lead & 0x1F) << 6) | (ptr[1] & 0x3F), 2}
        end
      elsif lead < 0xF0
        if avail >= 3 && ptr[1] & 0xC0 == 0x80 && ptr[2] & 0xC0 == 0x80
          cp = ((lead & 0x0F) << 12) | ((ptr[1] & 0x3F).to_i32 << 6) | (ptr[2] & 0x3F)
          return {cp, 3} if cp >= 0x800 && cp & 0xF800 != 0xD800
        end
      elsif avail >= 4 && ptr[1] & 0xC0 == 0x80 && ptr[2] & 0xC0 == 0x80 && ptr[3] & 0xC0 == 0x80
        cp = ((lead & 0x07) << 18) | ((ptr[1] & 0x3F).to_i32 << 12) | ((ptr[2] & 0x3F).to_i32 << 6) | (ptr[3] & 0x3F)
        return {cp, 4} if 0x10000 <= cp <= 0x10FFFF && lead < 0xF8
      end
      subpart(ptr, avail, lead)
    end

    # The ill-formed, or cut off, sequence at *ptr* that `decode` found.
    private def self.subpart(ptr : UInt8*, avail : Int32, lead : Int32) : {Int32, Int32}
      if lead < 0xC2
        return {REPLACEMENT, 1}
      elsif lead < 0xE0
        need, low, high, cp = 1, 0x80, 0xBF, lead & 0x1F
      elsif lead < 0xF0
        need, low, high, cp = 2, (lead == 0xE0 ? 0xA0 : 0x80), (lead == 0xED ? 0x9F : 0xBF), lead & 0x0F
      elsif lead < 0xF5
        need, low, high, cp = 3, (lead == 0xF0 ? 0x90 : 0x80), (lead == 0xF4 ? 0x8F : 0xBF), lead & 0x07
      else
        return {REPLACEMENT, 1}
      end
      i = 1
      while i <= need
        return {REPLACEMENT, -i} if i >= avail
        byte = ptr[i].to_i32
        return {REPLACEMENT, i} unless low <= byte <= high
        cp = (cp << 6) | (byte & 0x3F)
        low, high = 0x80, 0xBF
        i &+= 1
      end
      {cp, i}
    end

    # Number of printable ASCII bytes (U+0020 to U+007E) at the start of *ptr*, at most *avail*.
    @[AlwaysInline]
    def self.ascii(ptr : UInt8*, avail : Int32) : Int32
      n = 0
      while n &+ 8 <= avail
        word = uninitialized UInt64
        (ptr + n).copy_to(pointerof(word).as(UInt8*), 8)
        flipped = word ^ PRINTABLE_HIGH
        break unless (word | ((word &- PRINTABLE_LOW) & ~word) | ((flipped &- ONES) & ~flipped)) & HIGH_BITS == 0
        n &+= 8
      end
      while n < avail && 0x20 <= ptr[n] < 0x7F
        n &+= 1
      end
      n
    end
  end
end
