require 'discordrb'
require 'yaml'
require 'faye/websocket'
require 'eventmachine'
require 'json'

# apt-get install libopus-dev libsodium-dev ffmpeg

@bot = nil
@ws = nil
@thread = nil
@admins = {
  "122908555178147840" => true
}
@volume = 0.5
@current_song = {}
running = true
client_id = ENV["CLIENT_ID"]
default_ws_url = 'wss://listen.moe/api/v2/socket'
@ws_url = ENV["WEBSOCKET_URL"] || default_ws_url

@add_url = "https://discordapp.com/api/oauth2/authorize?client_id=#{client_id}&scope=bot&permissions=0"


Signal.trap("INT") do
  puts "Stopping..."
  EventMachine::stop_event_loop
  if !running
    puts "Force stopping..."
    exit(1)
  end
  running = false
end

def start_bot!(client_id)
  @thread = Thread.new do

    @bot = Discordrb::Bot.new token: ENV["BOT_TOKEN"], client_id: client_id

    @bot.message(start_with: "yui hi") do |event|
      event.respond("Hello~!")
    end

    @bot.message(start_with: "yui volume") do |event|
      if @admins.has_key?("#{event.user.id}")
        tokens = event.message.content.split(" ")
        @volume = tokens[2].to_f
        event.respond("Okie~! Be right baack")
        stop_bot!
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

    voice_chan = @bot.channel(ENV["CHANNEL_ID"])
    voice = @bot.voice_connect(voice_chan)
    voice.adjust_average = true
    voice.volume = @volume
    voice.play_file(ENV["STREAM_URL"] || "http://listen.moe:9999/stream")

    @bot.stop
    @bot = nil
  end

  loop do
    sleep(1)
    break if @bot
  end
end

def stop_bot!
  @bot.stop
  @thread.join
end

def ensure_bot!(client_id)

  connected = true
  begin
    connected = @bot.connected?
    @bot.dnd
    @bot.online
  rescue => e
    puts e
    connected = false
  end

  if !connected
    begin
      @bot.stop
    rescue => e
    end
    puts "Bot not running. Starting up."
    start_bot!(client_id)
  end

  if !@ws
    @ws = Faye::WebSocket::Client.new(@ws_url)

    @ws.on :open do |event|
      puts "Opened websocket to #{@ws_url}"
    end

    @ws.on :message do |event|
      puts "Received websocket message"
      p event.data
      begin
        @current_song = JSON.parse(event.data)
        @current_song["start_time"] = Time.now.to_i
        @bot.game = "#{@current_song["song_name"]} by #{@current_song["artist_name"]}"
      rescue
      end
    end

    @ws.on :close do |event|
      puts "Closed websocket"
      @ws = nil
    end
  end
end

EM.run {
  ensure_bot!(client_id)
  EventMachine::PeriodicTimer.new(10) do
    ensure_bot!(client_id)
    @bot.game = "#{@current_song["artist_name"]} - #{@current_song["song_name"]}"
  end
}

stop_bot!
