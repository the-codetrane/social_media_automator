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

  # Remove incomplete tool-use turns so the chat history is valid before calling the API.
  #
  # Two cases handled:
  #   1. Empty assistant messages — a placeholder persisted when the stream opened but never
  #      filled in (crashed before any content arrived).
  #   2. Incomplete turns — assistant message with tool_calls but not all results persisted
  #      (crashed mid-turn). Counts don't match, so Anthropic would reject the turn.
  #
  # Complete parallel turns (N>1 tool_calls with all N results) are valid and left intact.
  # They are stored as N separate :tool messages, which Anthropic rejects in that split form;
  # the payload patch in config/initializers/ruby_llm.rb merges them back into the single
  # user message the API requires.
  def repair_orphaned_tool_messages(chat)
    return unless chat.respond_to?(:messages_association)

    chat.messages_association.includes(ruby_llm_tool_calls: :result).order(:id).each do |message|
      next unless message.role.to_s == "assistant"

      calls = message.ruby_llm_tool_calls
      if calls.empty? && message.content.blank?
        message.destroy
      elsif calls.any? { |call| call.result.nil? }
        calls.filter_map(&:result).each(&:destroy)
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
