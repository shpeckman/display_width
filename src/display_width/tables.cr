# src/display_width/tables.cr
require "./props"

module DisplayWidth
  {% begin %}
    {% data = read_file("#{__DIR__}/../../data/tables.bin") %}
    {% line = data.lines.first %}
    {% header = line.split(" ") %}
    {% unless header.size == 5 && header[0] == "DISPLAY-WIDTH" && (header[3] == "1" || header[3] == "2") %}
      {% raise "data/tables.bin: not a display_width table (run make tables)" %}
    {% end %}
    {% shift = header[2].to_i %}
    {% props_at = line.size + 1 %}
    {% stage1_at = props_at + 2 * header[4].to_i %}
    {% stage2_at = stage1_at + header[3].to_i * (0x110000 >> shift) %}
    {% unless data.bytesize > stage2_at && (data.bytesize - stage2_at) % (1 << shift) == 0 %}
      {% raise "data/tables.bin: truncated (run make tables)" %}
    {% end %}

    # Unicode version of the tables.
    UNICODE_VERSION = {{ header[1] }}

    # :nodoc:
    SHIFT = {{ shift }}

    # :nodoc:
    MASK = {{ (1 << shift) - 1 }}_u32

    # :nodoc:
    STAGE1_WIDE = {{ header[3] == "2" }}

    # :nodoc:
    TABLES = {{ data }}

    # :nodoc:
    PROPS_AT = {{ props_at }}

    # :nodoc:
    STAGE1_AT = {{ stage1_at }}

    # :nodoc:
    STAGE2_AT = {{ stage2_at }}
  {% end %}

  # :nodoc:
  # Properties of *codepoint*; those of U+0000 (invalid) outside the code space.
  @[AlwaysInline]
  def self.props(codepoint : Int32) : Props
    cp = codepoint.to_u32!
    cp = 0_u32 if cp > 0x10FFFF
    t = TABLES.to_unsafe
    i = (cp >> SHIFT).to_i32!
    block = if STAGE1_WIDE
              t[STAGE1_AT &+ (i << 1)].to_i32 | (t[STAGE1_AT &+ (i << 1) &+ 1].to_i32 << 8)
            else
              t[STAGE1_AT &+ i].to_i32
            end
    j = t[STAGE2_AT &+ (block << SHIFT) &+ (cp & MASK).to_i32!].to_i32 << 1
    Props.new(t[PROPS_AT &+ j].to_u16 | (t[PROPS_AT &+ j &+ 1].to_u16 << 8))
  end
end
