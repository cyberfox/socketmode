require_relative 'basic_bot'

class MyBot < BasicBot
  command '/echo' do |command, text, channel, info, client|
    { response_type: 'ephemeral', text: text }
  end

  command'/echoe' do |command, text, channel, info, client|
    client.chat_postMessage(channel: channel, text: "Did a reverse!")
    { response_type: 'ephemeral', text: text.reverse }
  end

  mention /(?i)hello/ do |text, event, channel, client|
    client.chat_postMessage(channel: channel, text: "Hello <@#{event.user}>!")
    true
  end

  mention /(?i)good\s?bye/ do |text, event, channel, client|
    client.chat_postMessage(channel: channel, text: "Catch you soon, <@#{event.user}>!")
    true
  end
end

MyBot.start
