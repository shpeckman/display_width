# bench/width.cr
require "./bench_helper"

LINES = {
  "ASCII" => "  def render(screen : Screen, row : Int32) : Nil # draws one status line, 80 columns ",
  "Latin" => "Größenänderung für Fenster: Überschrift, Säulen, Zwischenräume und Ränder neu",
  "CJK"   => "漢字とかなの混じった文章を端末に表示するときの幅を計算します。全角文字が多い。",
  "emoji" => "\u{1F469}\u{200D}\u{1F4BB} ok \u{1F1F3}\u{1F1F1} \u{1F44B}\u{1F3FD} \u{263A}\u{FE0F} \u{231A}\u{FE0E} " \
             "1\u{FE0F}\u{20E3} \u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F} deploy \u{1F680} " \
             "done \u{2705} \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466} \u{1F389}",
  "combining" => "e\u{0301} a\u{0308} \u{0915}\u{094D}\u{0937} \u{0E01}\u{0E33} \u{1100}\u{1161}\u{11A8} " \
                 "n\u{0303}o\u{0302} Z\u{0335}a\u{0336}l\u{0337}g\u{0338}o",
}

LINES.each do |name, line|
  bytes = line.to_slice
  chars = line.chars
  Bench.group("#{name}: #{line.bytesize} bytes, #{DisplayWidth.of(line)} cells") do |job|
    job.report("of(String)") { Bench.keep(DisplayWidth.of(line)) }
    job.report("of(Array(Char))") { Bench.keep(DisplayWidth.of(chars)) }
    job.report("each_cluster") do
      DisplayWidth.each_cluster(bytes) { |offset, size, width| Bench.keep(offset &+ size &+ width) }
    end
    job.report("Stream#advance") { Bench.keep(DisplayWidth::Stream.new.advance(bytes)) }
    job.report("chars.sum of(Char)") { Bench.keep(chars.sum { |char| DisplayWidth.of(char) }) }
    job.report("stdlib each_grapheme (no widths)") do
      count = 0
      line.each_grapheme { count &+= 1 }
      Bench.keep(count)
    end
  end
end
