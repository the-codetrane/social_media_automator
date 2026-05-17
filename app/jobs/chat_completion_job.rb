# frozen_string_literal: true

# Generates the next assistant response for a Chat by calling the LLM.
#
# The user message is persisted by ChatsController#create_message before this
# job is enqueued. RubyLLM persists an empty assistant placeholder when the
# response stream opens, then updates it with the completed content; both events
# fire callbacks on Message that broadcast to the chat's Turbo stream.
class ChatCompletionJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat = Chat.find(chat_id)
    SocialMediaPostAgent.find(chat_id, user: chat.user).complete
  rescue RubyLLM::Error => e
    Rails.logger.error("[ChatCompletionJob] LLM error for Chat##{chat_id}: #{e.message}")
    broadcast_error(chat_id, e.message)
  end

  private

  def broadcast_error(chat_id, message)
    stream = "chat_#{chat_id}"
    Turbo::StreamsChannel.broadcast_remove_to(stream, target: "thinking")
    Turbo::StreamsChannel.broadcast_append_to(
      stream,
      target: "chat-messages",
      partial: "chats/error",
      locals: { message: message }
    )
  end
end
