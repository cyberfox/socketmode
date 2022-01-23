require_relative 'basic_bot'

class MyBot < BasicBot
  command '/echo' do |_, text, channel, info, client|
    { response_type: 'ephemeral', text: text }
  end

  command'/echoe' do |_, text, channel, info, client|
    client.chat_postMessage(channel: channel, text: "Did a reverse!")
    { response_type: 'ephemeral', text: text.reverse }
  end

  mention /(?i)hello/ do |text, match, event, channel, client|
    client.chat_postMessage(channel: channel, text: "Hello <@#{event.user}>!")
    true
  end

  mention /(?i)good\s?bye/ do |text, match, event, channel, client|
    client.chat_postMessage(channel: channel, text: "Catch you soon, <@#{event.user}>!")
    true
  end

  message /(?i)what time (is it|it is)/ do |text, match, event, channel, client|
    client.chat_postMessage(channel: channel, text: "The time is now #{Time.now.strftime("%B %-d, %Y at at %I:%M%p")}")
  end
end

MyBot.start
