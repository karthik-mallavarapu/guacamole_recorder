require './guacamole_parser'
require './image_processor'
require 'RMagick'
require 'socket'
require 'pry'
require 'thread'
require 'open3'


module ScreenRecorder
  include GuacamoleParser
  include ImageProcessor

  # Record method creates one thread for communicating 
  # with the server and another for periodically write 
  # buffered image to the named pipe.
  def record
    begin
      @recording_thread = Thread.new do
        begin
          guacd_remote_connect
        rescue Errno::ECONNRESET => e
          puts "Logged out..reconnecting"
          retry
        end  
      end
      @create_img_thread = Thread.new do 
        process_image
      end
    rescue Exception => e
      raise e
    end
  end

  def recording_thread
    @recording_thread
  end
  
  def create_img_thread
    @create_img_thread
  end

  def ffmpeg_pid
    @ffmpeg_pid
  end
  
  private

  # Creates a socket connection with the guacd server for sending/receiving 
  # instructions.
  def guacd_remote_connect
    socket = Socket.tcp(@guac_host, @guac_port.to_i)
    socket.print select 
    socket.flush
    carryover_instruction = "" 
    socket.while_reading do |buf|
      t = nil
      @start = true
      instructions = buf.split(';')
      if instructions[0]
        instructions[0] = carryover_instruction + instructions[0]
        if buf[-1] != ';'
          carryover_instruction = instructions[instructions.size - 1]
          instructions.delete_at(instructions.size - 1)
        elsif buf[-1] == ';'
          carryover_instruction = ""  
        end
      end    
      instructions.each do |i|
        parsed_instr = parse(i)
        if parsed_instr != nil
          if parsed_instr[:opcode] == 'args'
            socket.print client_handshake(parsed_instr[:count]) 
            socket.flush
          elsif parsed_instr[:opcode] == 'sync'
            t = parsed_instr[:data].to_i - 100
            socket.print "4.sync,13.#{t};"
            socket.flush
          else
            apply_instructions(parsed_instr)  
          end  
        end
      end
    end
    socket.close  
  end
  
  # Based on the received opcode, respective instruction handler method is called. 
  def apply_instructions(parsed_instr)
    if parsed_instr[:opcode] == 'png'
      apply_png(parsed_instr)
    elsif parsed_instr[:opcode] == 'copy'
      apply_copy(parsed_instr)
    elsif parsed_instr[:opcode] == 'rect'
      apply_rect(parsed_instr)
    elsif parsed_instr[:opcode] == 'cursor'
      apply_cursor(parsed_instr)
    elsif parsed_instr[:opcode] == 'cfill'
      apply_cfill(parsed_instr)
    elsif parsed_instr[:opcode] == 'transfer'
      apply_transfer(parsed_instr)
    end  
  end
  
  # Apply operation for png instruction adds the received png image 
  # to the buffer. 
  def apply_png(parsed_instr)
    layer = parsed_instr[:dst_layer]
    if layer.to_i < 0
      img = Magick::Image.read_inline(parsed_instr[:data]).first
      @png_buffer[layer] = img
    else  
      add_to_buffer(parsed_instr[:data], parsed_instr[:x_offset], parsed_instr[:y_offset])  
    end  
  end

  # Applies the copy operation. Based on the source & destination layer values 
  # an image chunk is copied from source to destination.
  def apply_copy(parsed_instr)
    layer = parsed_instr[:src_layer]
    dst_layer = parsed_instr[:dst_layer]
    if layer.to_i != 0
      if @png_buffer[layer]
        img = @png_buffer[layer].crop(parsed_instr[:src_x_offset].to_i, 
          parsed_instr[:src_y_offset].to_i, parsed_instr[:src_width].to_i, 
          parsed_instr[:src_height].to_i)
        if dst_layer.to_i == 0
          composite_operation(img, parsed_instr[:x_offset].to_i, 
            parsed_instr[:y_offset].to_i, Magick::OverCompositeOp)
        else
          img = @png_buffer[layer].crop(parsed_instr[:src_x_offset].to_i, 
          parsed_instr[:src_y_offset].to_i, parsed_instr[:src_width].to_i, 
          parsed_instr[:src_height].to_i)
          if @png_buffer[dst_layer]
            @png_buffer[dst_layer].composite!(img, parsed_instr[:x_offset].to_i, 
            parsed_instr[:y_offset].to_i, Magick::OverCompositeOp)
          end
        end    
      end  
    elsif layer.to_i == 0
      img = @buffer.crop(parsed_instr[:src_x_offset].to_i, 
        parsed_instr[:src_y_offset].to_i, parsed_instr[:src_width].to_i, 
        parsed_instr[:src_height].to_i)
      if dst_layer.to_i == 0
        composite_operation(img, parsed_instr[:x_offset], 
          parsed_instr[:y_offset], Magick::OverCompositeOp)
      else
        @png_buffer[dst_layer] = img
      end  
    end
  end

  def apply_cursor(parsed_instr)
    layer = parsed_instr[:src_layer]
    if @png_buffer[layer]
      img = @png_buffer[layer].crop(parsed_instr[:src_x_offset].to_i, 
        parsed_instr[:src_y_offset].to_i, parsed_instr[:width].to_i, 
        parsed_instr[:height].to_i)
      composite_operation(img, parsed_instr[:x_offset], parsed_instr[:y_offset], 
        Magick::OverCompositeOp)    
    end  
  end

  def apply_rect(parsed_instr)
    layer = parsed_instr[:dst_layer]
    @png_buffer[layer] = @buffer.crop(parsed_instr[:x_offset].to_i, 
      parsed_instr[:y_offset].to_i, parsed_instr[:width].to_i, 
      parsed_instr[:height].to_i)
        
  end

  # Applies color fill.
  def apply_cfill(parsed_instr)
    layer = parsed_instr[:src_layer]
    if @png_buffer[layer]
      @png_buffer[layer].colorize(0, 0, 0, 1, "black")
    end    
  end


  def apply_transfer(parsed_instr)
    layer = parsed_instr[:src_layer]
    dst_layer = parsed_instr[:dst_layer]
    if @png_buffer[layer]
      img = @png_buffer[layer]
      transfer_img = img.crop(parsed_instr[:src_x_offset].to_i, 
        parsed_instr[:src_y_offset].to_i, parsed_instr[:src_width].to_i, 
        parsed_instr[:src_height].to_i)
      composite_operation(transfer_img, parsed_instr[:x_offset], 
        parsed_instr[:y_offset], Magick::XorCompositeOp)
    end  
  end

  # Applies the size operation
  def apply_size(parsed_instr)
    layer = parsed_instr[:layer]
    if @check
      @buffer = Magick::Image.new(parsed_instr[:width].to_i, parsed_instr[:height].to_i)
      @check = false
    end  
  end

  # Client handshake to initiate the connection with the server.
  def client_handshake(count)
    handshake_instr = "#{size}#{audio}#{video}#{connect(count)}"
  end

  # Select instruction specifying the protocol.
  def select
    "6.select,3.#{@protocol};"
  end

  # Audio instruction.
  def audio
    "5.audio;"
  end

  # Video instruction.
  def video
    "5.video;"
  end

  # Specifies the optimal client resolution.
  def size
    "4.size,#{@width.to_s.size}.#{@width},#{@height.to_s.size}.#{@height};"
  end

  # Initiates a connection with the guacd, based on the specified connection parameters.  
  def connect(arg_count)
    connect_instr = ""
    padding_count = 0
    padding_str = ""
    if @protocol == "vnc"
      connect_instr = "7.connect,#{@host.size}.#{@host},#{@port.to_s.size}.#{@port},3.yes"
      padding_count = arg_count - 3
    elsif @protocol == "rdp"
      connect_instr = "7.connect,#{@host.size}.#{@host},#{@port.to_s.size}.#{@port},0.,#{@username.size}.#{@username},#{@password.size}.#{@password},#{@width.to_s.size}.#{@width},#{@height.to_s.size}.#{@height}"
      padding_count = arg_count - 7
    end
    # Padding count varies for RDP and VNC. It determines the number of padding 
    # instructions to be added.
    padding_str = ""
    padding_count.times do
      padding_str = padding_str + ",0."
    end
    connect_instr+padding_str+";"
  end

  # Disconnects the connection.
  def disconnect
    "10.disconnect;"
  end

end

class IO
  def while_reading(data = nil)
    while buf = readpartial_rescued(1024)
      data << buf  if data
      yield buf  if block_given?
    end
    data
  end
 
  private
 
  def readpartial_rescued(size)
    readpartial(size)
  rescue EOFError
    nil
  end
end