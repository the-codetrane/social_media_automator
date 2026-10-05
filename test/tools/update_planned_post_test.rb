# frozen_string_literal: true

require "test_helper"

class UpdatePlannedPostTest < ActiveSupport::TestCase
  setup do
    @post = planned_posts(:draft_post)
    @tool = UpdatePlannedPost.new
  end

  test "sets collaborators in platform_payload, stripping @ and duplicates" do
    result = @tool.execute(id: @post.id, collaborators: [ "@themakeouts", "mikeandthetvs", "themakeouts" ])

    assert_nil result[:error]
    assert_equal %w[themakeouts mikeandthetvs], result[:collaborators]
    assert_equal %w[themakeouts mikeandthetvs], @post.reload.platform_payload["collaborators"]
  end

  test "leaves collaborators untouched when the param is omitted" do
    @post.update!(platform_payload: { "collaborators" => [ "themakeouts" ] })

    result = @tool.execute(id: @post.id, caption: "New caption")

    assert_equal [ "themakeouts" ], result[:collaborators]
    assert_equal [ "themakeouts" ], @post.reload.platform_payload["collaborators"]
  end

  test "an empty array clears collaborators" do
    @post.update!(platform_payload: { "collaborators" => [ "themakeouts" ] })

    result = @tool.execute(id: @post.id, collaborators: [])

    assert_equal [], result[:collaborators]
    assert_not @post.reload.platform_payload.key?("collaborators")
  end

  test "keeps carousel ids when setting both in one call" do
    ids = [ media_assets(:sample_image).id, media_assets(:sample_image_2).id ]

    @tool.execute(id: @post.id, media_asset_ids: ids, collaborators: [ "themakeouts" ])

    payload = @post.reload.platform_payload
    assert_equal ids, payload["carousel_asset_ids"]
    assert_equal [ "themakeouts" ], payload["collaborators"]
  end

  test "rejects more than three collaborators" do
    result = @tool.execute(id: @post.id, collaborators: %w[a b c d])

    assert_match(/at most 3/, result[:error])
    assert_nil @post.reload.platform_payload
  end

  test "rejects collaborators on non-Instagram posts" do
    result = @tool.execute(id: planned_posts(:scheduled_post).id, collaborators: [ "themakeouts" ])

    assert_match(/only supported on Instagram/, result[:error])
  end
end
