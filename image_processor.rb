require 'base64'

module ImageProcessor

  # Adds a partial image to the image buffer
  def add_to_buffer(img_b64, x_offset, y_offset)
    img = Magick::Image.read_inline(img_b64).first
    composite_operation(img, x_offset, y_offset, Magick::OverCompositeOp)
  end
 
  # Composite operation to compose the buffer image. 
  def composite_operation(img, x_offset, y_offset, composite_op)
    @semaphore.synchronize {
      @buffer.composite!(img, x_offset.to_i, y_offset.to_i, composite_op)
    }
  end

  # Creates an image to be fed to ffmpeg from the buffer. Call this method 
  # periodically depending on the framerate requirement.
  def process_image
    sleep 4 
    @ffmpeg = IO.popen("/usr/local/bin/ffmpeg -f image2pipe -vcodec png -r 4 -i imagepipe.png -metadata title=\"Test Video\" -pix_fmt yuv420p -threads 4 -y output.mp4 >> encoding.log 2>&1")
    @ffmpeg_pid = @ffmpeg.pid
      outpipe = open("imagepipe.png", 'w')
      while true 
          @buffer.format = 'png'
          @buffer.write(outpipe)
          outpipe.flush
        sleep 0.1
      end
  end

end
