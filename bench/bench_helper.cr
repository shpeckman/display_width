# bench/bench_helper.cr
require "benchmark"
require "../src/display_width"

module Bench
  WARMUP      = 500.milliseconds
  CALCULATION = 2.seconds

  class_property sink = 0_u64

  def self.group(title : String, & : Benchmark::IPS::Job ->) : Nil
    puts
    puts title
    Benchmark.ips(warmup: WARMUP, calculation: CALCULATION) { |job| yield job }
  end

  def self.keep(value : Int) : Nil
    @@sink &+= value.to_u64!
  end
end
