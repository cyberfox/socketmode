require_relative 'basic_bot'
require 'active_support/concern'

module AddEchoe
  extend ActiveSupport::Concern
  included do
    command '/echoe' do |_, text, channel, info, client|
      client.chat_postMessage(channel: channel, text: "Did a reverse!")
      { response_type: 'ephemeral', text: text.reverse }
    end
  end
end

module TimeHandler
  extend ActiveSupport::Concern
  included do
    message /(?i)what time (is it|it is)/ do |text, match, event, channel, client|
      client.chat_postMessage(channel: channel, text: "The time is now #{Time.now.strftime("%B %-d, %Y at at %I:%M%p")}")
    end
  end
end

module GreetingsHandler
  extend ActiveSupport::Concern
  included do
    mention /(?i)hello/ do |text, match, event, channel, client|
      client.chat_postMessage(channel: channel, text: "Hello <@#{event.user}>!")
      true
    end

    mention /(?i)good\s?bye/ do |text, match, event, channel, client|
      client.chat_postMessage(channel: channel, text: "Catch you soon, <@#{event.user}>!")
      true
    end
  end
end

class MyBot < BasicBot
  command '/echo' do |_, text, channel, info, client|
    { response_type: 'ephemeral', text: text }
  end

  include AddEchoe
  include TimeHandler
  include GreetingsHandler
end

MyBot.start
