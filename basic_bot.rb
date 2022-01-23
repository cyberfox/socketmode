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
    response = http.request(request)
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

    unless self.class.behaviors.empty?
      self.class.behaviors.each do |kind, key_block_map|
        puts "Processing kind #{kind} - #{key_block_map.keys.inspect}"
        case kind
        when :mentions
          key_block_map.each {|pattern, block| register_mention(pattern, &block) }
        when :commands
          key_block_map.each {|cmd, block| register_command(cmd, &block) }
        when :messages
          key_block_map.each {|pattern, block| register_message(pattern, &block)}
        end
      end
    end

    @reconnect = false
  end

  def self.behaviors
    @behaviors
  end

  def register_command(cmd, &block)
    @registered_commands ||= Hash.new
    @registered_commands[cmd] ||= Array.new
    @registered_commands[cmd] << block
  end

  def register_mention(pattern, &block)
    @registered_mentions ||= Hash.new
    @registered_mentions[pattern] = block
  end

  def register_message(pattern, &block)
    @registered_messages ||= Hash.new
    @registered_messages[pattern] = block
  end

  def slash(payload)
    cmd = payload['command']
    if (callbacks = @registered_commands[cmd])
      callbacks.each do |cb|
        # command, text, info (payload), client
        result = cb.yield(cmd, payload['text'], payload[:channel_id], payload, @client)
        return result if result
      end
    end
  end

  def mention(event)
    cleaned_text = event.text.gsub(/^<@[A-Z0-9]+>\s*/, '')
    handled = false
    @registered_mentions.each do |pattern, callback|
      match = cleaned_text.match(pattern)
      if match
        handled = true
        callback.yield(cleaned_text, match, event, event.channel, @client)
      end
    end

    # If anything matched, we don't say this.  If something matched and didn't like
    # the result, it has to handle its own errors.
    unless handled
      # p({channel: event.channel, text: 'Sorry, I don\'t know that command.'})
      client.chat_postMessage({channel: event.channel, text: 'Sorry, I don\'t know that command.'})
    end
  end

  def message(event)
    @registered_messages&.each do |pattern, callback|
      match = event.text.match(pattern)
      if match
        callback.yield(event.text, match, event, event.channel, @client)
      end
    end
  end

  def unrecognized(message)
    # For messages that aren't 'hello', 'slash_commands', or 'events_api'
    # we get all here.  Not sure what that'll be yet. TODO
  end

  def unrecognized_event(message)
    # For event_api messages that aren't 'message', or 'app_mention'
    # we get all here.  Not sure what that'll be yet. TODO
  end

  def hello(connection_info)
    # Do what you will; this gets called each re-connection, so it's not a 'just once'
  end

  def event(payload)
    event = Message.new(payload[:event])
    case event.type
    when 'message'
      message(event)
    when 'app_mention'
      mention(event)
    else
      unrecognized_event(event)
    end
  end

  def allow_bot?
    false
  end

  def self.start
    loop do
      bot = self.new
      yield bot if block_given?

      EM.run do
        trap('TERM') { stop }
        trap('INT') { stop }

        ws = Faye::WebSocket::Client.new(bot.wsurl + '&debug_reconnects=true')

        ws.on :open do |event|
          p [:open]
        end

        ws.on :message do |event|
          message = Message.new(JSON.parse(event.data))
          # Instantly ack if it doesn't accept a response payload.
          acked = bot.ack(ws, message) if message.envelope_id? && !message.accepts_response_payload

          payload = nil
          skip = false
          if message.payload && message.payload['event'] && message.payload['event']['bot_id'] != nil
            skip = !bot.allow_bot?
          end

          unless skip
            p [:message, event.data]

            case message.type
            when 'hello' then bot.hello message.connection_info
            when 'slash_commands' then payload = bot.slash message.payload
            when 'events_api' then bot.event message.payload
            when 'disconnect' then @reconnect ||= message.reason == 'refresh_requested'
            else bot.unrecognized message
            end
          end

          bot.ack(ws, message, payload) if message.envelope_id && !acked
        end

        ws.on :close do |event|
          p [:close, event.code, event.reason]
          ws = nil
          EM.stop
        end
      end
      break unless @reconnect
    end
  end

  def self.add_behavior(kind, key, block)
    @behaviors ||= Hash.new
    @behaviors[kind] ||= Hash.new
    @behaviors[kind][key] = block
  end

  def self.command(cmd, &block)
    add_behavior(:commands, cmd, block)
  end

  def self.mention(pattern, &block)
    add_behavior(:mentions, pattern, block)
  end

  def self.message(pattern, &block)
    add_behavior(:messages, pattern, block)
  end

  def ack(ws, message, payload = nil)
    ack = { payload: payload } if payload
    ack ||= {}
    ack['envelope_id'] = message['envelope_id']
    ws.send(ack.to_json)

    true
  end
end
