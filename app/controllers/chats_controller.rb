# frozen_string_literal: true

class ChatsController < ApplicationController
  MODELS = [
    {
      id: "claude-haiku-4-5-20251001",
      display_name: "Claude Haiku 4.5",
      tagline: "Fast & lightweight",
      description: "Best for quick questions and simple tasks where speed matters most.",
      strengths: [ "Fastest response times", "Most economical", "Good for high-volume use" ],
      limitations: [ "Less nuanced reasoning", "May miss subtlety in complex prompts" ]
    },
    {
      id: "claude-sonnet-4-6",
      display_name: "Claude Sonnet 4.6",
      tagline: "Previous default",
      description: "Reliable for all social media drafting, scheduling, and content management.",
      strengths: [ "Strong writing & reasoning", "Handles all tools reliably", "Good speed/quality balance" ],
      limitations: [ "Slower than Haiku", "Overkill for very simple lookups" ]
    },
    {
      id: "claude-sonnet-5",
      display_name: "Claude Sonnet 5",
      tagline: "Balanced — default",
      description: "Next-generation Sonnet for drafting, scheduling, and content management, at a lower price than Sonnet 4.6.",
      strengths: [ "Newest Sonnet generation", "Cheaper per token than Sonnet 4.6", "Good speed/quality balance" ],
      limitations: [ "Slower than Haiku", "Overkill for very simple lookups" ]
    },
    {
      id: "claude-opus-4-8",
      display_name: "Claude Opus 4.8",
      tagline: "Most capable",
      description: "Best for complex creative writing, multi-step workflows, and nuanced reasoning.",
      strengths: [ "Highest quality output", "Best at nuanced writing", "Strongest multi-step reasoning" ],
      limitations: [ "Slowest response time", "Most expensive per request" ]
    },
    {
      id: "claude-opus-5",
      display_name: "Claude Opus 5",
      tagline: "Newest Opus",
      description: "Next-generation Opus for the hardest writing and multi-step work, at the same price as Opus 4.8.",
      strengths: [ "Newest Opus generation", "Best at nuanced writing", "Strongest multi-step reasoning" ],
      limitations: [ "Slowest response time", "Most expensive per request" ]
    }
  ].freeze

  # A conversation is resent in full on every turn, so its context size is what drives cost.
  # Past this many tokens we start a fresh chat instead of letting one thread grow without
  # bound — two runaway threads accounted for roughly 90% of one month's API spend.
  MAX_CONTEXT_TOKENS = 120_000

  before_action :set_chat
  helper_method :available_models

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

    roll_conversation_if_oversized

    if upload.present?
      media_asset = create_media_asset_from_upload(upload)
      @chat.ask_later(content, with: media_asset.file)
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
    @chat.with_model(model_id, provider: "anthropic", assume_model_exists: true)

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
    chat = Chat.find_by(id: session[:chat_id], user: Current.user) || build_chat
    reconcile_model_with_mode(chat)
    session[:chat_id] = chat.id
    @chat = chat
  end

  # The models the picker offers: the local server's model while LocalLlm is on (it can't
  # serve a Claude model ID), the Claude lineup otherwise.
  def available_models
    LocalLlm.enabled? ? [ LocalLlm.model_entry ] : MODELS
  end

  # A chat keeps the model it was created with, so flipping LOCAL_LLM_URL between server
  # restarts would send a Claude model ID to the local server, or the local alias to
  # Anthropic. Move a chat that crossed that line onto a model the current mode can serve;
  # chats already on the right side are left exactly as they are.
  def reconcile_model_with_mode(chat)
    on_local_model = chat.model&.model_id == LocalLlm.model_id
    return if on_local_model == LocalLlm.enabled?

    preferred = session[:chat_model]
    target = valid_model?(preferred) ? preferred : SocialMediaPostAgent.model[:model]
    chat.with_model(target, provider: "anthropic", assume_model_exists: true)
  end

  def build_chat
    chat = SocialMediaPostAgent.create!(user: Current.user)
    chat.update!(user: Current.user)
    preferred = session[:chat_model]
    if valid_model?(preferred) && preferred != chat.model_id
      chat.with_model(preferred, provider: "anthropic", assume_model_exists: true)
    end
    chat
  end

  # Start a fresh conversation once the current one's context grows too large.
  # Rolling happens as a new message is sent, so the thread on screen stays readable
  # until the user actually continues it.
  def roll_conversation_if_oversized
    return if conversation_tokens < MAX_CONTEXT_TOKENS

    @chat = build_chat
    session[:chat_id] = @chat.id
    flash[:notice] = "Started a new conversation — the previous one got long enough to slow down and get expensive."
  end

  # Size of the context the API last saw for this chat. The provider reports it per
  # call, so the newest successful usage entry is an exact measure rather than an estimate.
  # Anthropic splits the prompt across three counters -- uncached input, cache reads and
  # cache writes -- so all three have to be summed to get the whole context back.
  def conversation_tokens
    last = @chat.ruby_llm_usages.where(operation: "chat", status: "succeeded").last
    return 0 unless last

    last.input_tokens.to_i + last.cache_read_tokens.to_i + last.cache_write_tokens.to_i
  end

  def valid_model?(model_id)
    available_models.any? { |m| m[:id] == model_id }
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
    asset.file.attach(io: upload, filename: upload.original_filename, content_type: upload.content_type, key: "Images From Chat/#{SecureRandom.base36}")
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
