require 'ffi-portaudio'
require 'base32'
require_relative '../lib/morse_protocol.rb'

include FFI::PortAudio

$freq = 440
$starttime = Time.now
$recv_spec = Array.new
$recv = Array.new
$recv_morse = Array.new

# from https://github.com/corbanbrook/fourier_transform
class FourierTransform
  attr_reader :spectrum, :bandwidth, :samplerate, :buffersize

  def initialize buffersize, samplerate
    @buffersize = buffersize
    @samplerate = samplerate
    @bandwidth = (2.0 / @buffersize) * (@samplerate / 2.0)
    @spectrum = Array.new

    build_reverse_table
    build_trig_tables
  end

  def build_reverse_table
    @reverse = Array.new(@buffersize)
    @reverse[0] = 0;

    limit = 1
    bit = @buffersize >> 1

    while (limit < @buffersize )
      (0...limit).each do |i|
        @reverse[i + limit] = @reverse[i] + bit
      end

      limit = limit << 1
      bit = bit >> 1
    end
  end

  def build_trig_tables
    @sin_lookup = Array.new(@buffersize)
    @cos_lookup = Array.new(@buffersize)
    (0...@buffersize).each do |i|
      @sin_lookup[i] = Math.sin(- Math::PI / i);
      @cos_lookup[i] = Math.cos(- Math::PI / i);
    end
  end

  def fft(buffer)
    raise Exception if buffer.length % 2 != 0 

    real = Array.new(buffer.length)
    imag = Array.new(buffer.length)

    (0...buffer.length).each do |i|
      real[i] = buffer[@reverse[i]]
      imag[i] = 0.0
    end

    halfsize = 1
    while halfsize < buffer.length
      phase_shift_step_real = @cos_lookup[halfsize]
      phase_shift_step_imag = @sin_lookup[halfsize]
      current_phase_shift_real = 1.0
      current_phase_shift_imag = 0.0
      (0...halfsize).each do |fft_step|
        i = fft_step
        while i < buffer.length
          off = i + halfsize
          tr = (current_phase_shift_real * real[off]) - (current_phase_shift_imag * imag[off])
          ti = (current_phase_shift_real * imag[off]) + (current_phase_shift_imag * real[off])
          real[off] = real[i] - tr
          imag[off] = imag[i] - ti
          real[i] += tr
          imag[i] += ti

          i += halfsize << 1
        end
        tmp_real = current_phase_shift_real
        current_phase_shift_real = (tmp_real * phase_shift_step_real) - (current_phase_shift_imag * phase_shift_step_imag)
        current_phase_shift_imag = (tmp_real * phase_shift_step_imag) + (current_phase_shift_imag * phase_shift_step_real)
      end

      halfsize = halfsize << 1
    end

    (0...buffer.length/2).each do |i|
      @spectrum[i] = 2 * Math.sqrt(real[i] ** 2 + imag[i] ** 2) / buffer.length
    end

    @spectrum
  end
end

WINDOW = 1024

class FFTStream < Stream
  def initialize
    @max = 1
    @fourier = FourierTransform.new(WINDOW, 44100)
  end

  def process(input, output, frameCount, timeInfo, statusFlags, userData)
    @fourier.fft input.read_array_of_int16(frameCount)

    $recv_spec.push(@fourier.spectrum[440])
    #p ($recv_spec.inject(0.0){|r,i| r+=i }/$recv_spec.size)

    if Time.now - $starttime > 0.3
      if ($recv_spec.inject(0.0){|r,i| r+=i }/$recv_spec.size) >= 0.1
        if $recv.last == 0
          if $recv.length >= 15
            # end of transmission
            $recv_morse.push(4)
            $recv = Array.new
          elsif $recv.length >= 7
            # letter seperator
            $recv_morse.push(2)
            $recv = Array.new
          elsif $recv.length >= 2
            # tone seperator
            $recv_morse.push(3)
            $recv = Array.new
          else
            # experimental
            $recv.push(0)
          end
        else
          #puts "1"
          $recv.push(1)
        end
      else
        if $recv.last == 1
          if $recv.length >= 5
            # "-"
            $recv_morse.push(1)
            $recv = Array.new
          elsif $recv.length >= 2
            # "."
            $recv_morse.push(0)
            $recv = Array.new
          else
            # experimental
            $recv.push(1)
          end
        else
          #puts "0"
          $recv.push(0)
        end
      end
      $starttime = Time.now
      puts "raw: #{$recv}"
      puts "mor: #{$recv_morse}"
      $recv_spec = Array.new
    end
    #p @fourier.spectrum[440]

:paContinue
  end
end

API.Pa_Initialize

input = API::PaStreamParameters.new
input[:device] = API.Pa_GetDefaultInputDevice
input[:channelCount] = 1
input[:sampleFormat] = API::Int16
input[:suggestedLatency] = 0
input[:hostApiSpecificStreamInfo] = nil

stream = FFTStream.new
stream.open(input, nil, 44100, WINDOW)
stream.start

=begin
at_exit { 
  stream.close
  API.Pa_Terminate
}
=end

loop { sleep 1
  c_recv  = $recv
  c_morse = $recv_morse
  output  = Array.new

  # 終了判定
  if c_recv.last == 0 && c_recv.length > 30

    # 先頭の非データを削除
    loop do
      if !(c_morse.first == 0 || c_morse.first == 1)
        c_morse.shift
      else
        break
      end
    end

    # 2連続する短音を長音に変換
    c_morse.each_with_index do |d, c|
      if c_morse[c] == 0 && c_morse[c+1] == 0
        c_morse[c] = 1
        c_morse.slice!(c+1)
      end
    end

    # 2連続するトーン間を文字間に変換
    c_morse.each_with_index do |d, c|
      if c_morse[c] == 3 && c_morse[c+1] == 3
        c_morse[c] = 2
        c_morse.slice!(c+1)
      end
    end

    # トーンセパレータを全削除
    c_morse.delete(3)

    puts "Formatted Data: #{c_morse}"

    while !c_morse.empty? do
      letter = Array.new
      loop do
        if c_morse.empty? then break end
        if c_morse.first != 2
          letter.push(c_morse.shift)
        else
          c_morse.shift
          break
        end
      end
      #puts "letter: #{letter}"
      #puts "mor: #{c_morse}"
      output.push(MorseProtocol::Table.key(letter))
    end
    p output
    p Base32.decode(output.join(''))
    exit
  end
}
