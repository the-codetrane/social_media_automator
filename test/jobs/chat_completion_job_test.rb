# frozen_string_literal: true

require "test_helper"

class ChatCompletionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @chat = chats(:chat_with_messages)
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  test "perform calls complete on the agent-configured chat" do
    completed = false

    stub_chat = Object.new
    stub_chat.define_singleton_method(:user) { nil }

    agent_chat = Object.new
    agent_chat.define_singleton_method(:complete) { completed = true }

    Chat.stub(:find, ->(_id) { stub_chat }) do
      SocialMediaPostAgent.stub(:find, ->(_id, **_kwargs) { agent_chat }) do
        ChatCompletionJob.perform_now(@chat.id)
      end
    end

    assert completed, "expected complete to be invoked on the agent-configured chat"
  end

  test "perform enqueues on the default queue" do
    assert_enqueued_with(job: ChatCompletionJob, queue: "default") do
      ChatCompletionJob.perform_later(@chat.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  test "perform broadcasts an error and removes thinking on RubyLLM::Error" do
    broadcasts = []

    stub_chat = Object.new
    stub_chat.define_singleton_method(:user) { nil }

    error_agent_chat = Object.new
    error_agent_chat.define_singleton_method(:complete) { raise RubyLLM::Error, "boom" }

    appended = ->(stream, **kwargs) { broadcasts << [ :append, stream, kwargs ] }
    removed  = ->(stream, **kwargs) { broadcasts << [ :remove, stream, kwargs ] }

    Chat.stub(:find, ->(_id) { stub_chat }) do
      SocialMediaPostAgent.stub(:find, ->(_id, **_kwargs) { error_agent_chat }) do
        Turbo::StreamsChannel.stub(:broadcast_append_to, appended) do
          Turbo::StreamsChannel.stub(:broadcast_remove_to, removed) do
            assert_nothing_raised do
              ChatCompletionJob.perform_now(@chat.id)
            end
          end
        end
      end
    end

    stream = "chat_#{@chat.id}"
    remove_event = broadcasts.find { |type, s, _| type == :remove && s == stream }
    append_event = broadcasts.find { |type, s, _| type == :append && s == stream }

    assert remove_event, "expected thinking indicator to be removed"
    assert_equal "thinking", remove_event.last[:target]

    assert append_event, "expected error message to be appended"
    assert_equal "chat-messages", append_event.last[:target]
    assert_equal "chats/error",   append_event.last[:partial]
    assert_equal "boom",          append_event.last.dig(:locals, :message)
  end
end
