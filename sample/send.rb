require 'base32'
require_relative '../lib/morse_protocol.rb'

class MorsePacket
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
      MorseProtocol::Table[c].each do |m|
        Speaker.unmute
        if m == 0 then sleep MorseProtocol::BeepTime end
        if m == 1 then sleep MorseProtocol::BeepTime * 3 end
        Speaker.mute
        sleep MorseProtocol::BeepTime
      end
      sleep MorseProtocol::BeepTime * 2
    end
  end
end

pa = MorsePacket.new("Sample")
pa.speak
