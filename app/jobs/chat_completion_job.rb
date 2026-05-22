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

  # Remove incomplete or broken tool-use turns so the chat history is valid before calling the API.
  #
  # Two cases handled:
  #   1. Incomplete turns — assistant message with tool_calls but not all results persisted
  #      (crashed mid-turn). Counts don't match.
  #   2. Parallel-tool-call turns — assistant message with N>1 tool_calls where all N results
  #      exist but are stored as N separate :tool messages. Anthropic requires all results for one
  #      turn in a single user message; the split format always causes a 400. Delete and let the
  #      agent redo the turn sequentially (parallel tool use is now disabled via calls: :one).
  def repair_orphaned_tool_messages(chat)
    return unless chat.respond_to?(:messages_association)

    chat.messages_association.includes(:tool_calls).order(:id).each do |message|
      next unless message.role.to_s == "assistant"

      if message.tool_calls.empty? && message.content.blank?
        message.destroy
      elsif message.tool_calls.any? && message.tool_calls.count != message.tool_results.count
        message.tool_results.each(&:destroy)
        message.destroy
      elsif message.tool_calls.count > 1 && message.tool_calls.count == message.tool_results.count
        # Parallel turn stored as split messages — broken format, must be redone.
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
