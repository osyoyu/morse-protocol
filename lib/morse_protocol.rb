# coding: UTF-8

# Morse Protocol
#
# Packet Header Information
#  0 -  3 : Version (defailt: 1)
#  4 -  7 : Header Size in octets (default: 4)
#  8 - 23 : Total Size in octets
# 24 - 31 : Header Checksum

require 'base32'
require './speak.rb'

class MorsePacket
  MorseShortTime = 1
  MorseTable = {
    "A" => [0, 1],
    "B" => [1, 0, 0, 0],
    "C" => [1, 0, 1, 0],
    "D" => [1, 0, 0],
    "E" => [0],
    "F" => [0, 0, 1, 0],
    "G" => [1, 1, 0],
    "H" => [0, 0, 0, 0],
    "I" => [0, 0],
    "J" => [0, 1, 1, 1],
    "K" => [1, 0, 1],
    "L" => [0, 1, 0, 0],
    "M" => [1, 1],
    "N" => [1, 0],
    "O" => [1, 1, 1],
    "P" => [0, 1, 1, 0],
    "Q" => [1, 1, 0, 1],
    "R" => [0, 1, 0],
    "S" => [0, 0, 0],
    "T" => [1],
    "U" => [0, 0, 1],
    "V" => [0, 0, 0, 1],
    "W" => [0, 1, 1],
    "X" => [1, 0, 0, 1],
    "Y" => [1, 0, 1, 1],
    "Z" => [1, 1, 0, 0],
    "1" => [0, 1, 1, 1, 1],
    "2" => [0, 0, 1, 1, 1],
    "3" => [0, 0, 0, 1, 1],
    "4" => [0, 0, 0, 0, 1],
    "5" => [0, 0, 0, 0, 0],
    "6" => [1, 0, 0, 0, 0],
    "7" => [1, 1, 0, 0, 0],
    "8" => [1, 1, 1, 0, 0],
    "9" => [1, 1, 1, 1, 0],
    "0" => [1, 1, 1, 1, 1]
  }

  def initialize(data)
    @version = 1
    @header_size = 4
    @total_size = @header_size + data.bytesize
    @checksum = 0
    @source_addr = 0
    @destination_addr = 0

    @packet = Array.new
    @packet.push(sprintf("%04B", @version).split(//))
    @packet.push(sprintf("%04B", @header_size).split(//))
    @packet.push(sprintf("%016B", @total_size).split(//))
    @packet.push(sprintf("%08B", @checksum).split(//))

    @packet.push(data.unpack("B*").first.split(//))

    @binary = [@packet.flatten.join].pack("B*")
  end

  def speak
    Speaker[Phasor.new]
    Speaker.synth.freq = 440
    Speaker.mute

    p morse_array = Base32.encode(@binary).gsub("=", "").split(//)
    morse_array.each do |c|
      MorseTable[c].each do |m|
        Speaker.unmute
        if m == 0 then sleep MorseShortTime end
        if m == 1 then sleep MorseShortTime * 3 end
        Speaker.mute
        sleep MorseShortTime
      end
      sleep MorseShortTime * 2
    end
  end
end

pa = MorsePacket.new("Sample")
pa.speak
