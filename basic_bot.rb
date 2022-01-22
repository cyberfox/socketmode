require 'uri'
require 'net/https'
require 'json'
require 'faye/websocket'
require 'eventmachine'
require 'hashie'
require 'slack-ruby-client'
require 'ap'

class NilClass
  def empty?
    true
  end
end

class Message < Hashie::Mash
  include Hashie::Extensions::MergeInitializer
  include Hashie::Extensions::IndifferentAccess
  include Hashie::Extensions::MethodAccessWithOverride
end

class BasicBot
  attr_accessor :wsurl, :client

  def initialize(app_token=ENV['SLACK_APP_TOKEN'], bot_token=ENV['SLACK_BOT_TOKEN'])
    @client = Slack::Web::Client.new(token: bot_token)

    uri = URI('https://slack.com/api/apps.connections.open')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{app_token}"
    puts "Making request:"
    ap request
    response = http.request(request)
    puts "Got response:"
    ap response
    if response.code_type == Net::HTTPOK
      answer = JSON.parse(response.body)
      if answer['ok']
        @wsurl = answer['url']
      else
        raise Exception.new(answer['error'])
      end
    else
      raise Exception.new(response.code_type)
    end
  end

  def slash(slash_message)
    if slash_message['command'] == '/echo'
      { response_type: 'ephemeral', text: slash_message['text'] }
    end
  end

  def hello(connection_info)
    # Do what you will; this gets called each re-connection, so it's not a 'just once'
  end

  def event(payload)
    event = Message.new(payload[:event])
    if event.type == 'message'
      message(event)
    elsif event.type == 'app_mention'
      mention(event)
    end
    # Handle arbitrary event messages, including type: 'message' and 'app_mention'
  end

  def message(event)
    # Do nothing for most messages.
  end

  def mention(event)
    # p({channel: event.channel, text: 'Sorry, I don\'t know that command.'})
    client.chat_postMessage({channel: event.channel, text: 'Sorry, I don\'t know that command.'})
  end

  def unrecognized(message)
    # For messages that aren't 'hello', 'slash_commands', or 'events_api'
    # we get all here.  Not sure what that'll be yet. TODO
  end
end

reconnect = false

def ack(ws, message, payload = nil)
  p "Acking..."
  ack = { payload: payload } if payload
  ack ||= {}
  ack['envelope_id'] = message['envelope_id']
  ws.send(ack.to_json)

  true
end

loop do
  bot = BasicBot.new

  EM.run do
    trap('TERM') { stop }
    trap('INT') { stop }

    ws = Faye::WebSocket::Client.new(bot.wsurl + '&debug_reconnects=true')

    ws.on :open do |event|
      p [:open]
    end

    ws.on :message do |event|
      p [:message, event.data]
      message = Message.new(JSON.parse(event.data))
      # Instantly ack if it doesn't accept a response payload.
      acked = ack(ws, message) if message.envelope_id? && message.accepts_response_payload

      payload = nil

      case message.type
        when 'hello' then bot.hello message.connection_info
        when 'slash_commands' then payload = bot.slash message.payload
        when 'app_mention' then bot.mention message.payload
        when 'events_api' then bot.event message.payload
        when 'disconnect' then reconnect ||= message.reason == 'refresh_requested'
        else bot.unrecognized message
      end

      ack(ws, message, payload) if message.envelope_id && !acked
    end

    ws.on :close do |event|
      p [:close, event.code, event.reason]
      ws = nil
      EM.stop
    end
  end
  break unless reconnect
end
