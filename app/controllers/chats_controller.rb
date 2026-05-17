# frozen_string_literal: true

class ChatsController < ApplicationController
  before_action :set_chat

  # GET /chat
  def chat
    @messages = @chat.messages.order(:created_at)
  end

  # POST /chat/messages
  def create_message
    content = params[:content].to_s.strip

    if content.blank?
      redirect_to chat_path, alert: "Message cannot be blank." and return
    end

    @chat.add_message(role: :user, content: content)
    broadcast_thinking
    ChatCompletionJob.perform_later(@chat.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "chat-form",
          partial: "chats/form",
          locals: { chat: @chat }
        )
      end
      format.html { redirect_to chat_path }
    end
  end

  # DELETE /chat
  def destroy
    @chat.destroy
    session[:chat_id] = nil
    redirect_to chat_path, notice: "Chat cleared. A new conversation has been started."
  end

  private

  def set_chat
    chat = Chat.find_by(id: session[:chat_id], user: Current.user)
    unless chat
      chat = SocialMediaPostAgent.create!(user: Current.user)
      chat.update!(user: Current.user)
    end
    session[:chat_id] = chat.id
    @chat = chat
  end

  def broadcast_thinking
    Turbo::StreamsChannel.broadcast_append_to(
      stream_name,
      target: "chat-messages",
      partial: "chats/thinking"
    )
  end

  def stream_name
    "chat_#{@chat.id}"
  end
end
