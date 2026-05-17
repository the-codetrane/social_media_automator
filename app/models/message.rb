class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments

  # User messages arrive via Chat#add_message → broadcast on create.
  # Assistant messages are first persisted empty by RubyLLM, then updated with
  # the completed response → broadcast on the content update.
  after_create_commit :broadcast_new_message,        if: :user_message?
  after_update_commit :broadcast_assistant_response, if: :assistant_response_completed?

  private

  def user_message?
    role.to_s == "user"
  end

  def assistant_response_completed?
    role.to_s == "assistant" && content.present? && saved_change_to_content?
  end

  def broadcast_new_message
    broadcast_remove_to stream_name, target: "chat-empty"
    broadcast_append_to stream_name,
                        target: "chat-messages",
                        partial: "chats/message",
                        locals: { message: self }
  end

  def broadcast_assistant_response
    broadcast_remove_to stream_name, target: "thinking"
    broadcast_append_to stream_name,
                        target: "chat-messages",
                        partial: "chats/message",
                        locals: { message: self }
  end

  def stream_name
    "chat_#{chat_id}"
  end
end
