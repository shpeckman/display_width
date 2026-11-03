# tools/gen_tables.cr
#
# Generates data/tables.bin (the per-code-point `DisplayWidth::Props`, embedded by
# src/display_width/tables.cr) and the conformance data in spec/data from the Unicode Character
# Database. Cell widths follow kitty's rules (docs/text-sizing-protocol, gen/wcwidth.py).
#
# data/tables.bin: the ASCII header line "DISPLAY-WIDTH <version> <shift> <stage-1 entry bytes>
# <props>\n", then the distinct props (little-endian UInt16 each), stage 1 (the block of every
# 2**shift code points, little-endian, 1 or 2 bytes each) and stage 2 (a props index per code
# point of each block).
#
# usage: crystal run tools/gen_tables.cr [-- UNICODE_DIR]   (a mirror of Public/<version>/)
require "http/client"
require "../src/display_width/props"

UNICODE_VERSION = "18.0.0"
SOURCE          = "https://www.unicode.org/Public/#{UNICODE_VERSION}"
OUT_TABLES      = "data/tables.bin"
OUT_SPEC        = "spec/data"
MAGIC           = "DISPLAY-WIDTH"
SIZE            = 0x110000
SHIFTS          = 4..10
WIDE_RANGES     = {0x3400..0x4DBF, 0x4E00..0x9FFF, 0xF900..0xFAFF, 0x20000..0x2FFFD, 0x30000..0x3FFFD}
SKIN_TONES      = 0x1F3FB..0x1F3FF
INDICATORS      = 0x1F1E6..0x1F1FF

def fetch(dir : String?, path : String) : String
  return File.read(File.join(dir, path)) if dir
  STDERR.puts "fetching #{path}"
  response = HTTP::Client.get("#{SOURCE}/#{path}")
  abort "#{path}: HTTP #{response.status_code}" unless response.success?
  response.body
end

def codepoints(spec : String) : Range(Int32, Int32)
  first, _, last = spec.partition("..")
  first.to_i(16)..(last.empty? ? first : last).to_i(16)
end

def each_record(text : String, & : Array(String) ->) : Nil
  text.each_line do |line|
    data = line.partition('#')[0].strip
    yield data.split(';').map(&.strip) unless data.empty?
  end
end

def each_range(text : String, & : Range(Int32, Int32), Array(String) ->) : Nil
  each_record(text) { |fields| yield codepoints(fields[0]), fields }
end

dir = ARGV[0]?
category = Array(String).new(SIZE, "Cn")
ignorable = Bytes.new(SIZE)
eaw_wide = Bytes.new(SIZE)
eaw_ambiguous = Bytes.new(SIZE)
gcb = Array(DisplayWidth::Break).new(SIZE, DisplayWidth::Break::Other)
incb = Array(DisplayWidth::Conjunct).new(SIZE, DisplayWidth::Conjunct::None)
pictographic = Bytes.new(SIZE)
emoji_base = Bytes.new(SIZE)
emoji_wide = Bytes.new(SIZE)

each_range(fetch(dir, "ucd/extracted/DerivedGeneralCategory.txt")) do |range, fields|
  range.each { |cp| category[cp] = fields[1] }
end

each_range(fetch(dir, "ucd/PropList.txt")) do |range, fields|
  range.each { |cp| ignorable[cp] = 1 } if fields[1] == "Other_Default_Ignorable_Code_Point"
end

each_range(fetch(dir, "ucd/EastAsianWidth.txt")) do |range, fields|
  case fields[1]
  when "W", "F" then range.each { |cp| eaw_wide[cp] = 1 }
  when "A"      then range.each { |cp| eaw_ambiguous[cp] = 1 }
  end
end
WIDE_RANGES.each { |range| range.each { |cp| eaw_wide[cp] = 1 unless eaw_ambiguous[cp] == 1 } }

each_range(fetch(dir, "ucd/auxiliary/GraphemeBreakProperty.txt")) do |range, fields|
  value = DisplayWidth::Break.parse?(fields[1]) || abort "unknown Grapheme_Cluster_Break #{fields[1]}"
  range.each { |cp| gcb[cp] = value }
end

each_range(fetch(dir, "ucd/DerivedCoreProperties.txt")) do |range, fields|
  next unless fields[1] == "InCB"
  value = DisplayWidth::Conjunct.parse?(fields[2]) || abort "unknown Indic_Conjunct_Break #{fields[2]}"
  range.each { |cp| incb[cp] = value }
end

each_range(fetch(dir, "ucd/emoji/emoji-data.txt")) do |range, fields|
  range.each { |cp| pictographic[cp] = 1 } if fields[1] == "Extended_Pictographic"
end

each_record(fetch(dir, "emoji/emoji-sequences.txt")) do |fields|
  sequence = fields[0].split
  case fields[1]
  when "Basic_Emoji"
    codepoints(sequence[0]).each do |cp|
      emoji_base[cp] = 1
      emoji_wide[cp] = 1 if sequence.size == 1
    end
  when "Emoji_Keycap_Sequence"
    emoji_base[sequence[0].to_i(16)] = 1
  when "RGI_Emoji_Flag_Sequence"
    sequence.each do |hex|
      emoji_base[hex.to_i(16)] = 1
      emoji_wide[hex.to_i(16)] = 1
    end
  when "RGI_Emoji_Tag_Sequence", "RGI_Emoji_Modifier_Sequence"
    emoji_base[sequence[0].to_i(16)] = 1
    emoji_wide[sequence[0].to_i(16)] = 1
  end
end

def mark?(cp : Int32, category : String, ignorable : Bool) : Bool
  cp == 0 || category.starts_with?('M') || category == "Cf" || ignorable || cp.in?(SKIN_TONES)
end

def noncharacter?(cp : Int32) : Bool
  cp & 0xFFFE == 0xFFFE || 0xFDD0 <= cp <= 0xFDEF
end

props = Array(UInt16).new(SIZE) do |cp|
  cells = if cp.in?(INDICATORS) || eaw_wide[cp] == 1 || emoji_wide[cp] == 1
            DisplayWidth::Cells::Two
          elsif mark?(cp, category[cp], ignorable[cp] == 1)
            DisplayWidth::Cells::Zero
          elsif eaw_ambiguous[cp] == 1
            DisplayWidth::Cells::Ambiguous
          else
            DisplayWidth::Cells::One
          end
  invalid = category[cp].in?("Cc", "Cs") || noncharacter?(cp)
  DisplayWidth::Props.pack(gcb[cp], incb[cp], pictographic[cp] == 1, emoji_base[cp] == 1, cells, invalid).bits
end

distinct = props.uniq.sort!
abort "too many distinct props (#{distinct.size})" if distinct.size > 256
index = distinct.each_with_index.to_h

record Layout, shift : Int32, entry : Int32, stage1 : Array(Int32), stage2 : Array(Bytes) do
  def bytesize(props : Int32) : Int32
    2 * props + entry * stage1.size + stage2.size * (1 << shift)
  end
end

layouts = SHIFTS.map do |shift|
  blocks = [] of Bytes
  ids = {} of Bytes => Int32
  stage1 = (0...SIZE).step(1 << shift).map do |base|
    block = Bytes.new(1 << shift) { |i| index[props[base + i]].to_u8 }
    ids[block] ||= (blocks << block; blocks.size - 1)
  end.to_a
  Layout.new(shift, blocks.size > 256 ? 2 : 1, stage1, blocks)
end
layout = layouts.min_by(&.bytesize(distinct.size))
abort "too many blocks (#{layout.stage2.size})" if layout.stage2.size > 0x10000

Dir.mkdir_p(File.dirname(OUT_TABLES))
File.open(OUT_TABLES, "wb") do |io|
  io << MAGIC << ' ' << UNICODE_VERSION << ' ' << layout.shift << ' ' << layout.entry << ' ' << distinct.size << '\n'
  distinct.each { |value| io.write_bytes(value, IO::ByteFormat::LittleEndian) }
  layout.stage1.each do |block|
    io.write_byte((block & 0xFF).to_u8)
    io.write_byte((block >> 8).to_u8) if layout.entry == 2
  end
  layout.stage2.each { |block| io.write(block) }
end

Dir.mkdir_p(OUT_SPEC)
File.write(File.join(OUT_SPEC, "GraphemeBreakTest.txt"), fetch(dir, "ucd/auxiliary/GraphemeBreakTest.txt"))
File.write(File.join(OUT_SPEC, "emoji-variation-sequences.txt"), fetch(dir, "ucd/emoji/emoji-variation-sequences.txt"))
File.open(File.join(OUT_SPEC, "emoji-qualified.txt"), "w") do |io|
  io.puts "# Fully-qualified and component sequences of emoji-test.txt, Unicode #{UNICODE_VERSION}"
  each_record(fetch(dir, "emoji/emoji-test.txt")) do |fields|
    io.puts fields[0] if fields[1]?.in?("fully-qualified", "component")
  end
end

STDERR.puts "#{OUT_TABLES}: #{layout.bytesize(distinct.size)} bytes, #{distinct.size} props, " \
            "#{layout.stage2.size} blocks of #{1 << layout.shift}"
