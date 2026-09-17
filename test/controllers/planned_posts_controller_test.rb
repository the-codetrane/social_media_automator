require "test_helper"

class PlannedPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @planned_post = planned_posts(:draft_post)
    @media_asset = media_assets(:sample_image)
    @social_template = social_templates(:instagram_default)
  end

  test "index redirects when not signed in" do
    get planned_posts_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get planned_posts_path
    assert_response :success
  end

  test "index defaults to showing scheduled posts only" do
    sign_in_as(@user)
    get planned_posts_path
    # Scheduled posts should appear
    assert_match "Amazing reel", response.body
    assert_match "Show tonight", response.body
    assert_match "Doors at 8", response.body
    # Draft and published posts should not appear
    assert_no_match "Beautiful sunset", response.body
    assert_no_match "Live on IG", response.body
  end

  test "index with status=published shows published posts" do
    sign_in_as(@user)
    get planned_posts_path, params: { status: "published" }
    assert_match "Live on IG", response.body
    assert_no_match "Amazing reel", response.body
  end

  test "index with platform filter shows only matching platform" do
    sign_in_as(@user)
    get planned_posts_path, params: { platforms: [ "instagram" ], status: "scheduled" }
    assert_match "Show tonight", response.body
    assert_no_match "Amazing reel", response.body  # youtube
    assert_no_match "Doors at 8", response.body    # facebook
  end

  test "index with no platform selected shows all platforms" do
    sign_in_as(@user)
    get planned_posts_path, params: { status: "scheduled" }
    assert_match "instagram", response.body
    assert_match "youtube", response.body
    assert_match "facebook", response.body
  end

  test "index shows scheduled badge for default filter" do
    sign_in_as(@user)
    get planned_posts_path
    assert_match "scheduled", response.body
  end

  test "index shows published badge when filtering by published" do
    sign_in_as(@user)
    get planned_posts_path, params: { status: "published" }
    assert_match "published", response.body
  end

  test "index shows hashtags" do
    sign_in_as(@user)
    get planned_posts_path, params: { status: "draft" }
    assert_match "#nature #sunset #photography", response.body
  end

  test "index shows external post id for published post" do
    sign_in_as(@user)
    get planned_posts_path, params: { status: "published" }
    assert_match "ig_post_abc", response.body
  end

  # Show action tests
  test "show redirects when not signed in" do
    get planned_post_path(@planned_post)
    assert_redirected_to new_session_path
  end

  test "show returns success when signed in" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_response :success
  end

  test "show displays post details" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_match @planned_post.caption, response.body
    # The badge renders the display name ("Instagram"), not the enum key.
    assert_match(/#{@planned_post.platform}/i, response.body)
  end

  test "show has edit link" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "a[href=?]", edit_planned_post_path(@planned_post)
  end

  test "show has back link to index" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "a[href=?]", planned_posts_path
  end

  test "show displays hashtags" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_match @planned_post.hashtags, response.body
  end

  test "show links to media asset" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "a[href=?]", media_asset_path(@planned_post.media_asset)
  end

  test "show displays image media preview" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "img[src=?]", @planned_post.media_asset.public_url
  end

  test "show displays video media preview" do
    sign_in_as(@user)
    video_post = planned_posts(:scheduled_post)
    get planned_post_path(video_post)
    assert_select "video" do
      assert_select "source[src=?]", video_post.media_asset.public_url
    end
  end

  test "show does not display media preview when no public url" do
    sign_in_as(@user)
    # Create a post with media asset that has no public URL
    post_no_url = PlannedPost.create!(
      user: @user,
      media_asset: media_assets(:sample_image_no_url),
      platform: :instagram,
      status: :draft,
      caption: "Test post"
    )
    get planned_post_path(post_no_url)
    assert_response :success
    # Scoped to main: the nav carries the site logo as an <img>.
    assert_select "main img", count: 0
    assert_select "main video", count: 0
  end

  test "show renders all carousel slides for a carousel post" do
    sign_in_as(@user)
    get planned_post_path(planned_posts(:carousel_post))
    assert_select "img[src=?]", media_assets(:sample_image).public_url
    assert_select "img[src=?]", media_assets(:sample_image_2).public_url
    assert_match "2 items", response.body
  end

  test "show renders carousel navigation controls for a carousel post" do
    sign_in_as(@user)
    get planned_post_path(planned_posts(:carousel_post))
    assert_select "[data-controller='carousel']"
    assert_select "[data-action='click->carousel#prev']"
    assert_select "[data-action='click->carousel#next']"
    assert_select "[data-carousel-target='dot']", count: 2
  end

  # Edit action tests
  test "edit redirects when not signed in" do
    get edit_planned_post_path(@planned_post)
    assert_redirected_to new_session_path
  end

  test "edit returns success when signed in" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_response :success
  end

  test "edit displays form with current values" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "textarea[name='planned_post[caption]']", text: /Beautiful sunset/
    assert_select "input[name='planned_post[hashtags]'][value=?]", @planned_post.hashtags
    assert_select "select[name='planned_post[status]']"
  end

  test "edit shows media asset select" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "select[name='planned_post[media_asset_id]']"
  end

  test "edit shows social template select" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "select[name='planned_post[social_template_id]']"
  end

  # Update action tests
  test "update redirects when not signed in" do
    patch planned_post_path(@planned_post), params: { planned_post: { caption: "New Caption" } }
    assert_redirected_to new_session_path
  end

  test "update changes post attributes" do
    sign_in_as(@user)
    patch planned_post_path(@planned_post), params: { planned_post: { caption: "Updated Caption" } }
    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal "Updated Caption", @planned_post.caption
  end

  test "update can change hashtags" do
    sign_in_as(@user)
    patch planned_post_path(@planned_post), params: { planned_post: { hashtags: "#newtag #updated" } }
    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal "#newtag #updated", @planned_post.hashtags
  end

  test "update can change status" do
    sign_in_as(@user)
    scheduled_time = 3.days.from_now
    patch planned_post_path(@planned_post), params: { planned_post: { status: "scheduled", scheduled_at: scheduled_time } }
    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal "scheduled", @planned_post.status
  end

  test "update shows success notice" do
    sign_in_as(@user)
    patch planned_post_path(@planned_post), params: { planned_post: { caption: "New" } }
    follow_redirect!
    assert_match "successfully updated", response.body
  end

  # Publish action tests
  test "publish redirects when not signed in" do
    post publish_planned_post_path(@planned_post)
    assert_redirected_to new_session_path
  end

  test "publish enqueues PublishInstagramPostJob for instagram post" do
    sign_in_as(@user)
    assert_enqueued_with(job: PublishInstagramPostJob) do
      post publish_planned_post_path(@planned_post)
    end
    assert_redirected_to planned_post_path(@planned_post)
    assert_match "Instagram", flash[:notice]
  end

  test "publish enqueues PublishFacebookPostJob for facebook post" do
    sign_in_as(@user)
    fb_post = planned_posts(:facebook_draft_post)
    assert_enqueued_with(job: PublishFacebookPostJob) do
      post publish_planned_post_path(fb_post)
    end
    assert_redirected_to planned_post_path(fb_post)
    assert_match "Facebook", flash[:notice]
  end

  # Every platform in the enum now has a publisher, so the controller's defensive
  # `else` branch can only be reached with a platform value the enum doesn't map.
  # Writing one straight to the column is the only way to exercise it.
  test "publish shows alert for unsupported platform" do
    sign_in_as(@user)
    orphan_post = planned_posts(:draft_post)
    orphan_post.update_column(:platform, 99)
    assert_nil PlannedPost.find(orphan_post.id).platform

    post publish_planned_post_path(orphan_post)

    assert_redirected_to planned_post_path(orphan_post)
    assert flash[:alert].present?
    assert_match(/not supported/i, flash[:alert])
  end

  test "index offers a filter chip for every platform" do
    sign_in_as(@user)
    get planned_posts_path

    # A third argument to assert_select is read as an equality test, not a
    # message, so assert the count explicitly instead.
    PlannedPost.platforms.keys.each do |platform|
      assert_select "input[name='platforms[]'][value=?]", platform, count: 1
    end
  end

  test "index filters down to tiktok posts only" do
    sign_in_as(@user)
    get planned_posts_path(platforms: [ "tiktok" ], status: "scheduled")

    assert_response :success
    assert assigns(:planned_posts).all?(&:tiktok?), "expected only tiktok posts"
    assert_includes assigns(:planned_posts).map(&:id), planned_posts(:due_tiktok_post).id
  end

  test "show has publish button for tiktok draft post" do
    sign_in_as(@user)
    get planned_post_path(planned_posts(:tiktok_draft_post))
    assert_select "form[action=?]", publish_planned_post_path(planned_posts(:tiktok_draft_post))
  end

  # Reproduces the production failure: publishing to an unconnected TikTok
  # account enqueued a job that immediately discarded the post as failed, with
  # the reason visible only in the server log.
  test "publish refuses when the platform is not connected" do
    sign_in_as(@user)
    tiktok_post = planned_posts(:tiktok_draft_post)
    @user.update!(tiktok_access_token: nil, tiktok_open_id: nil)

    assert_no_enqueued_jobs only: PublishTikTokPostJob do
      post publish_planned_post_path(tiktok_post)
    end

    assert_redirected_to planned_post_path(tiktok_post)
    assert_match(/TikTok is not connected/, flash[:alert])
    assert tiktok_post.reload.draft?, "the post must not be burned"
  end

  test "publish still works when the platform is connected" do
    sign_in_as(@user)
    tiktok_post = planned_posts(:tiktok_draft_post)
    assert @user.reload.tiktok_connected?

    assert_enqueued_with(job: PublishTikTokPostJob) do
      post publish_planned_post_path(tiktok_post)
    end
  end

  test "show surfaces the failure reason for a failed post" do
    sign_in_as(@user)
    tiktok_post = planned_posts(:tiktok_draft_post)
    tiktok_post.mark_failed!("User 1 has no TikTok access token")

    get planned_post_path(tiktok_post)

    assert_response :success
    assert_match "Publish failed", response.body
    assert_match "User 1 has no TikTok access token", response.body
  end

  test "publish queues PublishTikTokPostJob for a tiktok post" do
    sign_in_as(@user)
    tiktok_post = planned_posts(:tiktok_draft_post)

    assert_enqueued_with(job: PublishTikTokPostJob) do
      post publish_planned_post_path(tiktok_post)
    end
    assert_redirected_to planned_post_path(tiktok_post)
    assert_match "TikTok", flash[:notice]
  end

  test "show hides the re-verify button for platforms with no verifier" do
    sign_in_as(@user)
    tiktok_post = planned_posts(:tiktok_draft_post)
    tiktok_post.update!(status: :published, published_at: 1.hour.ago, external_post_id: "v_pub_001")

    get planned_post_path(tiktok_post)
    assert_select "form[action=?]", verify_planned_post_path(tiktok_post), count: 0
  end

  test "show has publish button for instagram draft post" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "form[action=?]", publish_planned_post_path(@planned_post)
  end

  test "show has publish button for facebook draft post" do
    sign_in_as(@user)
    get planned_post_path(planned_posts(:facebook_draft_post))
    assert_select "form[action=?]", publish_planned_post_path(planned_posts(:facebook_draft_post))
  end

  test "show does not have publish button for published post" do
    sign_in_as(@user)
    get planned_post_path(planned_posts(:published_post))
    assert_select "form[action=?]", publish_planned_post_path(planned_posts(:published_post)), count: 0
  end

  # Verify action tests
  test "verify redirects when not signed in" do
    post verify_planned_post_path(planned_posts(:published_post))
    assert_redirected_to new_session_path
  end

  test "verify enqueues VerifyPublishedPostJob for a published post" do
    sign_in_as(@user)
    published = planned_posts(:published_post)
    assert_enqueued_with(job: VerifyPublishedPostJob) do
      post verify_planned_post_path(published)
    end
    assert_redirected_to planned_post_path(published)
    assert_match "queued", flash[:notice]
  end

  test "verify shows alert when post is not published" do
    sign_in_as(@user)
    post verify_planned_post_path(@planned_post)
    assert_redirected_to planned_post_path(@planned_post)
    assert flash[:alert].present?
  end

  test "show has re-verify button for published post with external_post_id" do
    sign_in_as(@user)
    get planned_post_path(planned_posts(:published_post))
    assert_select "form[action=?]", verify_planned_post_path(planned_posts(:published_post))
  end

  test "show does not have re-verify button for draft post" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "form[action=?]", verify_planned_post_path(@planned_post), count: 0
  end

  test "show displays permalink link when platform_payload has permalink" do
    sign_in_as(@user)
    published = planned_posts(:published_post)
    published.update!(platform_payload: { "permalink" => "https://www.instagram.com/p/test123/" })
    get planned_post_path(published)
    assert_select "a[href=?]", "https://www.instagram.com/p/test123/"
  end

  test "show does not display permalink link when platform_payload has no permalink" do
    sign_in_as(@user)
    get planned_post_path(planned_posts(:published_post))
    assert_select "a[href^='https://www.instagram.com/p/']", count: 0
  end

  # URL decoding tests
  test "index decodes URL-encoded media asset names" do
    sign_in_as(@user)
    get planned_posts_path, params: { status: "draft" }
    assert_match "Big Guys BBQ", response.body
  end

  test "show decodes URL-encoded media asset name in link" do
    sign_in_as(@user)
    url_encoded_post = planned_posts(:url_encoded_asset_post)
    get planned_post_path(url_encoded_post)
    # The media asset link text should be decoded
    assert_match "Big Guys BBQ", response.body
    assert_select "a[href=?]", media_asset_path(url_encoded_post.media_asset), text: /Big Guys BBQ/
  end

  test "edit decodes URL-encoded media asset names in dropdown" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    # The select dropdown should show decoded names
    assert_match "Big Guys BBQ", response.body
  end

  test "edit shows post type radios" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "input[type='radio'][name='planned_post[post_type]'][value='single']"
    assert_select "input[type='radio'][name='planned_post[post_type]'][value='carousel']"
    assert_select "input[type='radio'][name='planned_post[post_type]'][value='story']"
  end

  test "edit hides the story radio on a platform without a stories publisher" do
    sign_in_as(@user)
    get edit_planned_post_path(planned_posts(:tiktok_draft_post))
    assert_select "input[type='radio'][name='planned_post[post_type]'][value='story']", count: 0
  end

  test "edit pre-selects story for a story post" do
    sign_in_as(@user)
    @planned_post.update!(platform_payload: { "post_type" => "story" })

    get edit_planned_post_path(@planned_post)
    assert_select "input[type='radio'][name='planned_post[post_type]'][value='story'][checked]"
  end

  test "edit pre-selects carousel for a carousel post" do
    sign_in_as(@user)
    get edit_planned_post_path(planned_posts(:carousel_post))
    assert_select "input[type='radio'][name='planned_post[post_type]'][value='carousel'][checked]"
  end

  test "edit pre-selects single for a non-carousel post" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "input[type='radio'][name='planned_post[post_type]'][value='single'][checked]"
  end

  test "edit only shows processed media assets in carousel picker" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    # All fixture assets have status: processed so they all appear
    assert_select "[data-carousel-select-target='checkbox']"
  end

  # Carousel update tests
  test "update with carousel post type sets carousel_asset_ids in platform_payload" do
    sign_in_as(@user)
    asset1 = media_assets(:sample_image)
    asset2 = media_assets(:sample_image_2)

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type: "carousel",
        caption: @planned_post.caption,
        hashtags: @planned_post.hashtags,
        status: @planned_post.status,
        carousel_asset_ids: [ asset1.id, asset2.id ]
      }
    }

    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal [ asset1.id, asset2.id ], @planned_post.platform_payload["carousel_asset_ids"]
    assert_equal asset1.id, @planned_post.media_asset_id
  end

  test "update with carousel preserves ordering of carousel_asset_ids" do
    sign_in_as(@user)
    asset1 = media_assets(:sample_image)
    asset2 = media_assets(:sample_image_2)

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type: "carousel",
        caption: @planned_post.caption,
        status: @planned_post.status,
        carousel_asset_ids: [ asset2.id, asset1.id ]
      }
    }

    @planned_post.reload
    assert_equal [ asset2.id, asset1.id ], @planned_post.platform_payload["carousel_asset_ids"]
    assert_equal asset2.id, @planned_post.media_asset_id
  end

  test "update with carousel type and fewer than 2 assets re-renders edit with error" do
    sign_in_as(@user)
    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type: "carousel",
        caption: @planned_post.caption,
        status: @planned_post.status,
        carousel_asset_ids: [ media_assets(:sample_image).id ]
      }
    }

    assert_response :unprocessable_entity
    assert_match "Carousel posts require at least 2 media assets", response.body
  end

  test "update with single post type clears carousel_asset_ids" do
    sign_in_as(@user)
    carousel = planned_posts(:carousel_post)

    patch planned_post_path(carousel), params: {
      planned_post: {
        post_type: "single",
        caption: carousel.caption,
        status: carousel.status,
        media_asset_id: media_assets(:sample_image).id
      }
    }

    assert_redirected_to planned_post_path(carousel)
    carousel.reload
    assert_nil carousel.platform_payload["carousel_asset_ids"]
    assert_equal media_assets(:sample_image).id, carousel.media_asset_id
  end

  test "show describes a published facebook story" do
    sign_in_as(@user)
    story = planned_posts(:facebook_draft_post)
    story.update!(
      status:           :published,
      external_post_id: "fb_story_001",
      published_at:     Time.current,
      platform_payload: { "post_type" => "story", "story_status" => "PUBLISHED" }
    )

    get planned_post_path(story)
    assert_response :success
    assert_match "Live on the Page.", response.body
  end

  test "show explains an unlisted story rather than showing nothing" do
    sign_in_as(@user)
    story = planned_posts(:facebook_draft_post)
    story.update!(
      status:           :published,
      external_post_id: "fb_story_001",
      published_at:     Time.current,
      platform_payload: { "post_type" => "story", "story_status" => "UNLISTED" }
    )

    get planned_post_path(story)
    assert_response :success
    assert_match "No longer listed", response.body
  end

  # Story update tests
  test "update with story post type records post_type in platform_payload" do
    sign_in_as(@user)

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type: "story",
        caption: @planned_post.caption,
        status: @planned_post.status,
        media_asset_id: media_assets(:sample_image).id
      }
    }

    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal "story", @planned_post.platform_payload["post_type"]
    assert_equal "story", @planned_post.post_type
  end

  test "update with story post type clears carousel_asset_ids" do
    sign_in_as(@user)
    carousel = planned_posts(:carousel_post)

    patch planned_post_path(carousel), params: {
      planned_post: {
        post_type: "story",
        caption: carousel.caption,
        status: carousel.status,
        media_asset_id: media_assets(:sample_image).id
      }
    }

    assert_redirected_to planned_post_path(carousel)
    carousel.reload
    assert_nil carousel.platform_payload["carousel_asset_ids"]
    assert_equal "story", carousel.post_type
  end

  # The caption is left alone rather than blanked: Instagram drops it on a
  # story, but switching back to a feed post should not have lost the text.
  test "update with story post type keeps the caption on the record" do
    sign_in_as(@user)

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type: "story",
        caption: "Kept for later",
        status: @planned_post.status,
        media_asset_id: media_assets(:sample_image).id
      }
    }

    @planned_post.reload
    assert_equal "Kept for later", @planned_post.caption
  end

  test "switching a story back to single clears post_type" do
    sign_in_as(@user)
    @planned_post.update!(platform_payload: { "post_type" => "story" })

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type: "single",
        caption: @planned_post.caption,
        status: @planned_post.status,
        media_asset_id: media_assets(:sample_image).id
      }
    }

    @planned_post.reload
    assert_nil @planned_post.platform_payload["post_type"]
    assert_equal "single", @planned_post.post_type
  end

  test "update with single post type succeeds with valid media_asset_id" do
    sign_in_as(@user)
    new_asset = media_assets(:sample_image_2)

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type: "single",
        caption: "Updated caption",
        status: @planned_post.status,
        media_asset_id: new_asset.id
      }
    }

    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal new_asset.id, @planned_post.media_asset_id
    assert_equal "Updated caption", @planned_post.caption
  end

  # ---------------------------------------------------------------------------
  # Instagram options — collaborators
  # ---------------------------------------------------------------------------

  test "edit renders the collaborator and audio pickers for instagram posts" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)

    assert_response :success
    assert_select "[data-controller='collaborator-select']"
    assert_select "[data-controller='audio-select']"
  end

  test "update stores normalized collaborators in platform_payload" do
    sign_in_as(@user)

    patch planned_post_path(@planned_post), params: {
      planned_post: { collaborators: [ "@chef_alex", " bakery_co ", "" ] }
    }

    assert_redirected_to planned_post_path(@planned_post)
    assert_equal [ "chef_alex", "bakery_co" ], @planned_post.reload.platform_payload["collaborators"]
  end

  test "update clears collaborators when none are submitted" do
    sign_in_as(@user)
    @planned_post.update!(platform_payload: { "collaborators" => [ "chef_alex" ] })

    patch planned_post_path(@planned_post), params: { planned_post: { caption: "No collabs" } }

    assert_redirected_to planned_post_path(@planned_post)
    assert_not @planned_post.reload.platform_payload.key?("collaborators")
  end

  test "update rejects more collaborators than Instagram allows" do
    sign_in_as(@user)

    patch planned_post_path(@planned_post), params: {
      planned_post: { collaborators: %w[one two three four] }
    }

    assert_response :unprocessable_entity
    assert_select "li", /at most 3 collaborators/
    assert_nil @planned_post.reload.platform_payload&.dig("collaborators")
  end

  test "update leaves platform_payload alone for non-instagram posts" do
    sign_in_as(@user)
    post = planned_posts(:youtube_draft_post)

    patch planned_post_path(post), params: {
      planned_post: { collaborators: [ "chef_alex" ] }
    }

    assert_redirected_to planned_post_path(post)
    assert_nil post.reload.platform_payload&.dig("collaborators")
  end

  # ---------------------------------------------------------------------------
  # Instagram options — audio
  # ---------------------------------------------------------------------------

  test "update stores the selected audio track" do
    sign_in_as(@user)

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        audio_id:     "587784541076604",
        audio_title:  "Birthday Wish",
        audio_artist: "Shuba"
      }
    }

    assert_redirected_to planned_post_path(@planned_post)
    payload = @planned_post.reload.platform_payload
    assert_equal "587784541076604", payload["audio_id"]
    assert_equal "Birthday Wish", payload["audio_title"]
    assert_equal "Shuba", payload["audio_artist"]
  end

  test "update clears the audio track when none is submitted" do
    sign_in_as(@user)
    @planned_post.update!(platform_payload: {
      "audio_id" => "587784541076604", "audio_title" => "Birthday Wish", "audio_artist" => "Shuba"
    })

    patch planned_post_path(@planned_post), params: { planned_post: { caption: "Silent" } }

    assert_redirected_to planned_post_path(@planned_post)
    payload = @planned_post.reload.platform_payload
    assert_not payload.key?("audio_id")
    assert_not payload.key?("audio_title")
  end

  test "update preserves carousel_asset_ids while setting collaborators" do
    sign_in_as(@user)
    image_1 = media_assets(:sample_image)
    image_2 = media_assets(:sample_image_2)

    patch planned_post_path(@planned_post), params: {
      planned_post: {
        post_type:          "carousel",
        carousel_asset_ids: [ image_1.id, image_2.id ],
        collaborators:      [ "chef_alex" ]
      }
    }

    assert_redirected_to planned_post_path(@planned_post)
    payload = @planned_post.reload.platform_payload
    assert_equal [ image_1.id, image_2.id ], payload["carousel_asset_ids"]
    assert_equal [ "chef_alex" ], payload["collaborators"]
  end

  # ---------------------------------------------------------------------------
  # Search endpoints
  # ---------------------------------------------------------------------------

  test "collaborator_search returns previously used usernames with counts" do
    sign_in_as(@user)
    @planned_post.update!(platform_payload: { "collaborators" => [ "chef_alex", "bakery_co" ] })

    get collaborator_search_planned_post_path(@planned_post), params: { q: "chef" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ { "username" => "chef_alex", "count" => 1 } ], body["collaborators"]
  end

  test "collaborator_search requires a signed-in user" do
    get collaborator_search_planned_post_path(@planned_post)
    assert_redirected_to new_session_path
  end

  test "audio_search returns tracks from the Audio API" do
    sign_in_as(@user)

    fake_service = Object.new
    fake_service.define_singleton_method(:search) do |audio_type:, query:|
      [ {
        "audio_id"                    => "587784541076604",
        "title"                       => "Birthday Wish",
        "display_artist"              => "Shuba",
        "audio_type"                  => audio_type,
        "duration_in_ms"              => 153760,
        "cover_artwork_thumbnail_uri" => "https://cdn.example.com/art.jpg"
      } ]
    end

    Instagram::AudioService.stub(:new, fake_service) do
      get audio_search_planned_post_path(@planned_post), params: { q: "birthday" }
    end

    assert_response :success
    track = JSON.parse(response.body)["tracks"].first
    assert_equal "587784541076604", track["audio_id"]
    assert_equal "Birthday Wish", track["title"]
    assert_equal "Shuba", track["artist"]
    assert_equal "2:33", track["duration"]
  end

  test "audio_search reports Instagram errors instead of failing silently" do
    sign_in_as(@user)

    fake_service = Object.new
    fake_service.define_singleton_method(:search) do |**|
      raise Instagram::TokenExpiredError, "User has no Instagram access token"
    end

    Instagram::AudioService.stub(:new, fake_service) do
      get audio_search_planned_post_path(@planned_post), params: { q: "x" }
    end

    assert_response :bad_gateway
    assert_match(/no Instagram access token/, JSON.parse(response.body)["error"])
  end

  test "audio_search falls back to the music catalogue for an unknown audio_type" do
    sign_in_as(@user)
    captured_type = nil

    fake_service = Object.new
    fake_service.define_singleton_method(:search) do |audio_type:, query:|
      captured_type = audio_type
      []
    end

    Instagram::AudioService.stub(:new, fake_service) do
      get audio_search_planned_post_path(@planned_post), params: { audio_type: "podcast" }
    end

    assert_response :success
    assert_equal "music", captured_type
  end
end
