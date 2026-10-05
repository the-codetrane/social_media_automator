# frozen_string_literal: true

require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
  end

  # ---------------------------------------------------------------------------
  # Auth gates
  # ---------------------------------------------------------------------------

  test "GET /chat redirects when not signed in" do
    get chat_path
    assert_redirected_to new_session_path
  end

  test "POST /chat/messages redirects when not signed in" do
    post chat_messages_path, params: { content: "hi" }
    assert_redirected_to new_session_path
  end

  test "DELETE /chat redirects when not signed in" do
    delete destroy_chat_path
    assert_redirected_to new_session_path
  end

  # ---------------------------------------------------------------------------
  # GET /chat
  # ---------------------------------------------------------------------------

  test "GET /chat renders the chat UI" do
    sign_in_as(@user)
    get chat_path
    assert_response :success
    assert_select "h1", text: "Chat"
    assert_select "form[action=?]", chat_messages_path
    assert_select "form[action=?]", destroy_chat_path
    assert_select "#chat-messages"
  end

  test "GET /chat creates a new chat when none is in the session" do
    sign_in_as(@user)
    assert_difference "Chat.count", 1 do
      get chat_path
    end
    assert_response :success
    assert_not_nil session[:chat_id]
  end

  test "GET /chat reuses the chat already tracked in the session" do
    sign_in_as(@user)
    get chat_path
    existing_chat_id = session[:chat_id]

    assert_no_difference "Chat.count" do
      get chat_path
    end
    assert_equal existing_chat_id, session[:chat_id]
  end

  test "GET /chat renders existing messages for the session chat" do
    sign_in_as(@user)
    # Seed a chat then attach a message before re-visiting.
    get chat_path
    chat = Chat.find(session[:chat_id])
    chat.messages.create!(role: "user", content: "Earlier message")

    get chat_path
    assert_response :success
    assert_match "Earlier message", response.body
  end

  test "GET /chat subscribes to the chat's turbo stream" do
    sign_in_as(@user)
    get chat_path
    assert_select "turbo-cable-stream-source"
  end

  # ---------------------------------------------------------------------------
  # POST /chat/messages
  # ---------------------------------------------------------------------------

  test "create_message persists the user message" do
    sign_in_as(@user)
    get chat_path
    chat = Chat.find(session[:chat_id])

    assert_difference -> { chat.messages.where(role: "user").count }, 1 do
      post chat_messages_path, params: { content: "What's the weather?" }
    end

    last = chat.messages.where(role: "user").order(:id).last
    assert_equal "What's the weather?", last.content
  end

  test "create_message strips and validates content" do
    sign_in_as(@user)
    get chat_path

    assert_no_difference "Message.count" do
      post chat_messages_path, params: { content: "   " }
    end
    assert_redirected_to chat_path
    assert_match(/blank/i, flash[:alert])
  end

  test "create_message enqueues a ChatCompletionJob with the chat id" do
    sign_in_as(@user)
    get chat_path
    chat_id = session[:chat_id]

    assert_enqueued_with(job: ChatCompletionJob, args: [ chat_id ]) do
      post chat_messages_path, params: { content: "Generate a haiku" }
    end
  end

  test "create_message responds with a turbo_stream that resets the form" do
    sign_in_as(@user)
    get chat_path

    post chat_messages_path,
         params:  { content: "ping" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match %r{\Atext/vnd\.turbo-stream\.html}, response.media_type
    assert_match %r{<turbo-stream\s+action="replace"\s+target="chat-form">}, response.body
  end

  test "create_message falls back to a redirect for plain HTML requests" do
    sign_in_as(@user)
    get chat_path
    post chat_messages_path, params: { content: "ping" }
    assert_redirected_to chat_path
  end

  # ---------------------------------------------------------------------------
  # POST /chat/messages — context rollover
  # ---------------------------------------------------------------------------

  test "create_message rolls to a new chat once the context grows too large" do
    sign_in_as(@user)
    get chat_path
    chat_id = session[:chat_id]
    record_context(Chat.find(chat_id), input_tokens: ChatsController::MAX_CONTEXT_TOKENS)

    post chat_messages_path, params: { content: "keep going" }

    assert_not_equal chat_id, session[:chat_id]
    assert_match(/new conversation/i, flash[:notice])
  end

  test "create_message counts cache write tokens toward the context size" do
    sign_in_as(@user)
    get chat_path
    chat_id = session[:chat_id]
    record_context(Chat.find(chat_id),
                   input_tokens: 10,
                   cache_write_tokens: ChatsController::MAX_CONTEXT_TOKENS)

    post chat_messages_path, params: { content: "keep going" }

    assert_not_equal chat_id, session[:chat_id]
  end

  test "create_message stays on the same chat while the context is small" do
    sign_in_as(@user)
    get chat_path
    chat_id = session[:chat_id]
    record_context(Chat.find(chat_id), input_tokens: 100, cache_read_tokens: 100, cache_write_tokens: 100)

    post chat_messages_path, params: { content: "keep going" }

    assert_equal chat_id, session[:chat_id]
  end

  # ---------------------------------------------------------------------------
  # POST /chat/messages — image attachment
  # ---------------------------------------------------------------------------

  test "create_message with an image creates a MediaAsset and attaches it to the message" do
    sign_in_as(@user)
    get chat_path
    chat = Chat.find(session[:chat_id])

    image = fixture_file_upload(
      Rails.root.join("test/fixtures/files/test_image.png"),
      "image/png"
    )

    assert_difference [ "MediaAsset.count", -> { chat.messages.where(role: "user").count } ], 1 do
      post chat_messages_path, params: { content: "What do you see?", attachment: image }
    end

    asset = MediaAsset.order(:id).last
    assert asset.image?
    assert asset.processed?
    assert asset.file.attached?

    message = chat.messages.where(role: "user").order(:id).last
    assert_equal "What do you see?", message.content
    assert message.attachments.attached?
  end

  test "create_message with image sets correct metadata on the MediaAsset" do
    sign_in_as(@user)
    get chat_path

    image = fixture_file_upload(
      Rails.root.join("test/fixtures/files/test_image.png"),
      "image/png"
    )

    post chat_messages_path, params: { content: "Describe this", attachment: image }

    asset = MediaAsset.order(:id).last
    assert_equal "image/png", asset.mime_type
    assert_not_nil asset.external_id
    assert_not_nil asset.first_seen_at
  end

  test "create_message with image still enqueues ChatCompletionJob" do
    sign_in_as(@user)
    get chat_path
    chat_id = session[:chat_id]

    image = fixture_file_upload(
      Rails.root.join("test/fixtures/files/test_image.png"),
      "image/png"
    )

    assert_enqueued_with(job: ChatCompletionJob, args: [ chat_id ]) do
      post chat_messages_path, params: { content: "Look at this", attachment: image }
    end
  end

  test "create_message with blank content and image rejects the request" do
    sign_in_as(@user)
    get chat_path

    image = fixture_file_upload(
      Rails.root.join("test/fixtures/files/test_image.png"),
      "image/png"
    )

    assert_no_difference [ "Message.count", "MediaAsset.count" ] do
      post chat_messages_path, params: { content: "   ", attachment: image }
    end
    assert_redirected_to chat_path
    assert_match(/blank/i, flash[:alert])
  end

  test "create_message with image responds with turbo_stream" do
    sign_in_as(@user)
    get chat_path

    image = fixture_file_upload(
      Rails.root.join("test/fixtures/files/test_image.png"),
      "image/png"
    )

    post chat_messages_path,
         params:  { content: "What's in this image?", attachment: image },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match %r{\Atext/vnd\.turbo-stream\.html}, response.media_type
    assert_match %r{<turbo-stream\s+action="replace"\s+target="chat-form">}, response.body
  end

  # ---------------------------------------------------------------------------
  # GET /chat — form structure
  # ---------------------------------------------------------------------------

  test "GET /chat renders the file input for image attachments" do
    sign_in_as(@user)
    get chat_path
    assert_select "input[type=file][name=attachment][accept='image/*']"
  end

  test "GET /chat renders the form with multipart encoding" do
    sign_in_as(@user)
    get chat_path
    assert_select "form[enctype='multipart/form-data'][action=?]", chat_messages_path
  end

  # ---------------------------------------------------------------------------
  # DELETE /chat
  # ---------------------------------------------------------------------------

  test "destroy deletes the current chat and clears the session entry" do
    sign_in_as(@user)
    get chat_path
    chat_id = session[:chat_id]

    assert_difference "Chat.count", -1 do
      delete destroy_chat_path
    end
    assert_nil Chat.find_by(id: chat_id)
    assert_nil session[:chat_id]
    assert_redirected_to chat_path
    assert_match(/cleared/i, flash[:notice])
  end

  test "destroy cascades to the chat's messages" do
    sign_in_as(@user)
    get chat_path
    chat = Chat.find(session[:chat_id])
    message_count = chat.messages.count
    chat.messages.create!(role: "user", content: "to be removed")

    assert_difference "Message.count", -(message_count + 1) do
      delete destroy_chat_path
    end
  end

  test "destroy followed by GET /chat starts a fresh chat" do
    sign_in_as(@user)
    get chat_path
    original = session[:chat_id]

    delete destroy_chat_path
    get chat_path
    assert_not_equal original, session[:chat_id]
  end

  private

  # Stand in for a provider response so the controller can read a context size back.
  def record_context(chat, input_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0)
    message = chat.messages.create!(role: "assistant", content: "ok")
    chat.ruby_llm_usages.create!(
      message: message,
      operation: "chat",
      status: "succeeded",
      provider: "anthropic",
      model: "claude-sonnet-4-6",
      input_tokens: input_tokens,
      cache_read_tokens: cache_read_tokens,
      cache_write_tokens: cache_write_tokens
    )
  end
end
