require 'discordrb'
require 'yaml'
require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'yaml'

# apt-get install libopus-dev libsodium-dev ffmpeg

@bot = nil
@ws = nil
@threads = []
@admins = {
  "122908555178147840" => true
}
@volume = 0.5
@current_song = {}

@running = true
client_id = ENV["CLIENT_ID"]
default_ws_url = 'wss://listen.moe/api/v2/socket'
@ws_url = ENV["WEBSOCKET_URL"] || default_ws_url

@add_url = "https://discordapp.com/api/oauth2/authorize?client_id=#{client_id}&scope=bot&permissions=0"


@log_queue = []
@log_channel = ENV["BOT_LOG_CHANNEL"] || "331596661954576385"

def log(message, type=:debug)
  @log_queue.push({time: Time.now.to_i, message: message})
  loop do
    curr_log = @log_queue.last
    begin
      @bot.channel(@log_channel).send_message("[YUI][#{type.to_s.upcase}][#{Time.at(curr_log[:time])}] #{curr_log[:message]}") if curr_log
      @log_queue.pop
    rescue
      break
    end
    break if @log_queue.length == 0
  end
end

stdout = StringIO.new
Discordrb::LOGGER.streams << stdout

Thread.new do
  loop do
    log(stdout.readline, :dsout)
    break if !@running
  end
end

Signal.trap("INT") do
  log "Stopping..."
  EventMachine::stop_event_loop
  if !@running
    log "Force stopping..."
    exit(1)
  end
  @running = false
end

def start_bot!(client_id)

  @bot = Discordrb::Bot.new token: ENV["BOT_TOKEN"], client_id: client_id

  @bot.message(start_with: "yui hi") do |event|
    event.respond("Hello~!")
  end

  @bot.message(start_with: "yui volume") do |event|
    if @admins.has_key?("#{event.user.id}")
      tokens = event.message.content.split(" ")
      @volume = tokens[2].to_f
      event.respond("Okie~! Be right baack")
      EventMachine::stop_event_loop
    end
  end

  @bot.message(start_with: "yui np") do |event|

    tstamp = Time.at(Time.now.to_i - @current_song["start_time"]).strftime("%M:%S")
    event.respond(<<-RESPONSE
**Now playing**
#{tstamp}
Song name: #{@current_song["song_name"]}
Artist name: #{@current_song["artist_name"]}
Anime name: #{@current_song["anime_name"]}
    RESPONSE
    )
  end

  @bot.run :async

  @threads = []

  ENV["CHANNEL_ID"].split(",").each do |chan_id|
    @threads << Thread.new do
      log "#{chan_id} Joined"
      begin
        voice_chan = @bot.channel(chan_id)
        voice = @bot.voice_connect(voice_chan)
        voice.adjust_average = false
        voice.adjust_offset = (ENV["ADJUST_OFFSET"] || 5).to_i
        voice.adjust_interval = (ENV["ADJUST_INTERVAL"] || 50).to_i
        voice.volume = @volume
        loop do
          log "#{chan_id} Started"
          voice.play_file(ENV["STREAM_URL"] || "http://listen.moe:9999/stream")
          log "#{chan_id} Stopped"
          break if !@running
        end
      rescue => e
        log "#{chan_id}: #{e.to_s.gsub("`", "'")}\n```\n#{e.backtrace.join("\n")}\n```", :error
      end
      log "#{chan_id} Exited"
    end
  end

end

def stop_bot!
  @bot.stop

  procs = `ps -A | grep ffmpeg`.split("\n").map{|x| x.split(" ")[0]}
  procs.each do |x|
    output = `kill #{x}`
    log "Killed #{x}: #{output.inspect}", :pkill
  end

  old = @running
  @running = false
  @threads.each {|x| x.join}
  @running = old
end

def ensure_bot!(client_id)

  connected = true
  begin
    connected = @bot.connected?
    @bot.dnd
    @bot.online
  rescue => e
    log e, :error
    connected = false
  end

  if !connected
    begin
      @bot.stop
    rescue => e
      log "#{e.to_s.gsub("`", "'")}\n```\n#{e.backtrace.join("\n")}\n```", :error
    end
    log "Bot not running. Starting up."
    start_bot!(client_id)
  end

  if !@ws
    @ws = Faye::WebSocket::Client.new(@ws_url)

    @ws.on :open do |event|
      log "Opened websocket to #{@ws_url}"
    end

    @ws.on :message do |event|
      data = nil
      begin
        data = JSON.parse(event.data)
      rescue => e
      end
      if (data)
        log "Received websocket message: \n```\n#{data.to_yaml}\n```"
        begin
          @current_song = JSON.parse(event.data)
          @current_song["start_time"] = Time.now.to_i
          @bot.game = "#{@current_song["song_name"]} by #{@current_song["artist_name"]}"
        rescue => e
          log "#{e.to_s.gsub("`", "'")}\n```\n#{e.backtrace.join("\n")}\n```", :error
        end
      end
    end

    @ws.on :close do |event|
      log "Closed websocket", :error
      @ws = nil
    end
  end
end

loop do
  EM.run {
    ensure_bot!(client_id)
    EventMachine::PeriodicTimer.new(10) do
      ensure_bot!(client_id)
      @bot.game = "#{@current_song["artist_name"]} - #{@current_song["song_name"]}"
    end
  }

  stop_bot!
  break if !@running
end