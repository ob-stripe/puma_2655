# frozen_string_literal: true

require 'sinatra'

get '/' do
  # Allocate some stuff and trigger GC
  a = {}
  100_000.times do |i|
    a[i] = Regexp.new('cat')
  end
  GC.start

  GC.stat.to_s
end
