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
    repair_orphaned_tool_messages(chat)
    SocialMediaPostAgent.find(chat_id, user: chat.user).complete
  rescue RubyLLM::Error, StandardError => e
    Rails.logger.error("[ChatCompletionJob] error for Chat##{chat_id}: #{e.class}: #{e.message}")
    broadcast_error(chat_id, e.message)
  end

  private

  # Remove incomplete tool-use turns so the chat history is valid before we call the API.
  # This is a pre-flight safety net for cases where a previous job run crashed mid-turn
  # (e.g. a tool raised StandardError) leaving orphaned tool_use blocks without tool_results.
  def repair_orphaned_tool_messages(chat)
    return unless chat.respond_to?(:messages_association)

    chat.messages_association.includes(:tool_calls).order(:id).each do |message|
      next unless message.role.to_s == "assistant"

      if message.tool_calls.empty? && message.content.blank?
        # Blank placeholder created by before_message callback that was never completed.
        message.destroy
      elsif message.tool_calls.any? && message.tool_calls.count != message.tool_results.count
        # Tool-use turn with missing results — destroy results then the turn itself.
        message.tool_results.each(&:destroy)
        message.destroy
      end
    end
  end

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
