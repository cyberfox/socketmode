require_relative 'basic_bot'

class MyBot < BasicBot
  command '/echo' do |command, text, channel, info, client|
    { response_type: 'ephemeral', text: text }
  end

  command'/echoe' do |command, text, channel, info, client|
    client.chat_postMessage(channel: channel, text: "Did a reverse!")
    { response_type: 'ephemeral', text: text.reverse }
  end
end

MyBot.start
