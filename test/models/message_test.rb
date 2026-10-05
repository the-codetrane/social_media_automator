# frozen_string_literal: true

require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:empty_chat)
  end

  def capture_broadcasts
    events = []
    Turbo::StreamsChannel.stub(:broadcast_append_to, ->(stream, **kw) { events << [ :append, stream, kw ] }) do
      Turbo::StreamsChannel.stub(:broadcast_remove_to, ->(stream, **kw) { events << [ :remove, stream, kw ] }) do
        yield
      end
    end
    events
  end

  # ---------------------------------------------------------------------------
  # User messages
  # ---------------------------------------------------------------------------

  test "creating a user message broadcasts an append to the chat stream" do
    events = capture_broadcasts do
      @chat.messages.create!(role: "user", content: "hi")
    end

    stream = "chat_#{@chat.id}"
    append = events.find { |type, s, _| type == :append && s == stream }
    assert append, "expected an append broadcast on the chat stream"
    assert_equal "chat-messages", append.last[:target]
    assert_equal "chats/message", append.last[:partial]
  end

  test "creating a user message also removes the empty-state placeholder" do
    events = capture_broadcasts do
      @chat.messages.create!(role: "user", content: "hi")
    end

    stream = "chat_#{@chat.id}"
    remove = events.find { |type, s, _| type == :remove && s == stream }
    assert remove, "expected an empty-state remove broadcast"
    assert_equal "chat-empty", remove.last[:target]
  end

  # ---------------------------------------------------------------------------
  # Assistant messages
  # ---------------------------------------------------------------------------

  test "creating an empty assistant placeholder does not broadcast" do
    events = capture_broadcasts do
      @chat.messages.create!(role: "assistant", content: "")
    end

    assert_empty events
  end

  test "filling in assistant content broadcasts a thinking-remove + append" do
    message = @chat.messages.create!(role: "assistant", content: "")

    events = capture_broadcasts do
      message.update!(content: "Here is the answer.")
    end

    stream = "chat_#{@chat.id}"
    remove = events.find { |type, s, _| type == :remove && s == stream }
    append = events.find { |type, s, _| type == :append && s == stream }

    assert remove, "expected the thinking indicator to be removed"
    assert_equal "thinking", remove.last[:target]

    assert append, "expected the assistant message to be appended"
    assert_equal "chat-messages", append.last[:target]
    assert_equal "chats/message", append.last[:partial]
  end

  test "touching an assistant message without a content change does not broadcast" do
    message = @chat.messages.create!(role: "assistant", content: "Hello")

    events = capture_broadcasts do
      message.update!(finish_reason: "stop")
    end

    assert_empty events
  end
end
