require 'pry'
require './screen_recorder'
require 'yaml'

class Recorder 
  include ScreenRecorder
    
  def initialize(config)
    # Initial config such as guacd server details, remote host 
    # addresses, user credentials.
    @host = config['remote_host']    
    @port = config['remote_port'].to_i
    @guac_host = config['guac_host']
    @guac_port = config['guac_port']
    @username = config['username']
    @password = config['password']
    @protocol = config['protocol']

    # Initialiaze image buffers and set default resolution.
    @png_buffer = Hash.new
    @rect_buffer = Hash.new
    @semaphore = Mutex.new
    @buffer = Magick::Image.new(1024, 768)
    @width = "1024"
    @height = "768"

    # Create a named pipe for writing image files.
    system("mkfifo imagepipe.png")
  end
end

config = YAML.load_file 'config.yml'
raise "Missing config info about guac host" unless config['guac_host']
raise "Missing config info about guac port" unless config['guac_port']
raise "Missing config info about remote host" unless config['remote_host']
raise "Missing config info about remote port" unless config['remote_port']
raise "Missing config info about username" unless config['username']
raise "Missing config info about password" unless config['password']
raise "Missing config info about protocol" unless config['protocol']

recorder = Recorder.new(config)
recorder.record
sleep 60
recorder.recording_thread.terminate
recorder.create_img_thread.terminate
system("rm imagepipe.png")