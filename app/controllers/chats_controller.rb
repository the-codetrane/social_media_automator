# frozen_string_literal: true

class ChatsController < ApplicationController
  MODELS = [
    {
      id: "claude-haiku-4-5-20251001",
      display_name: "Claude Haiku",
      tagline: "Fast & lightweight",
      description: "Best for quick questions and simple tasks where speed matters most.",
      strengths: [ "Fastest response times", "Most economical", "Good for high-volume use" ],
      limitations: [ "Less nuanced reasoning", "May miss subtlety in complex prompts" ]
    },
    {
      id: "claude-sonnet-4-6",
      display_name: "Claude Sonnet",
      tagline: "Balanced — default",
      description: "Reliable for all social media drafting, scheduling, and content management.",
      strengths: [ "Strong writing & reasoning", "Handles all tools reliably", "Good speed/quality balance" ],
      limitations: [ "Slower than Haiku", "Overkill for very simple lookups" ]
    },
    {
      id: "claude-opus-4-8",
      display_name: "Claude Opus",
      tagline: "Most capable",
      description: "Best for complex creative writing, multi-step workflows, and nuanced reasoning.",
      strengths: [ "Highest quality output", "Best at nuanced writing", "Strongest multi-step reasoning" ],
      limitations: [ "Slowest response time", "Most expensive per request" ]
    }
  ].freeze

  before_action :set_chat

  # GET /chat
  def chat
    @messages = @chat.messages.order(:created_at)
  end

  # POST /chat/messages
  def create_message
    content = params[:content].to_s.strip
    upload = params[:attachment]

    if content.blank?
      redirect_to chat_path, alert: "Message cannot be blank." and return
    end

    if upload.present?
      media_asset = create_media_asset_from_upload(upload)
      @chat.create_user_message(content, with: media_asset.file)
    else
      @chat.add_message(role: :user, content: content)
    end

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

  # POST /chat/model
  def select_model
    model_id = params[:model_id]
    return redirect_to chat_path, alert: "Unknown model." unless valid_model?(model_id)

    session[:chat_model] = model_id
    @chat.with_model(model_id, provider: "anthropic", assume_exists: true)

    redirect_to chat_path
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
      preferred = session[:chat_model]
      if valid_model?(preferred) && preferred != chat.model_id
        chat.with_model(preferred, provider: "anthropic", assume_exists: true)
      end
    end
    session[:chat_id] = chat.id
    @chat = chat
  end

  def valid_model?(model_id)
    MODELS.any? { |m| m[:id] == model_id }
  end

  def create_media_asset_from_upload(upload)
    asset = MediaAsset.create!(
      external_id: SecureRandom.uuid,
      media_type: :image,
      status: :processed,
      first_seen_at: Time.current,
      mime_type: upload.content_type,
      file_size: upload.size
    )
    asset.file.attach(upload)
    asset
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
