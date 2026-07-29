# frozen_string_literal: true

# Swap in fake TikTok credentials for the duration of a block.
#
# CI runs without RAILS_MASTER_KEY, so Rails.application.credentials decrypts to
# nothing there. Any test that exercises the OAuth flow has to supply its own
# credentials rather than lean on the developer's local master.key — otherwise
# it passes locally and fails on CI with TikTok::ConfigurationError.
module TikTokCredentialsHelper
  DEFAULT_TIKTOK_CREDENTIALS = {
    production: { client_key: "aw_test_prod", client_secret: "test_prod_secret" },
    sandbox:    { client_key: "sbaw_test_sand", client_secret: "test_sand_secret" }
  }.freeze

  # @param tiktok [Hash] the hash that Rails.application.credentials.tiktok
  #   should return for the duration of the block
  def with_tiktok_credentials(tiktok = DEFAULT_TIKTOK_CREDENTIALS, &block)
    creds        = Rails.application.credentials
    original_dig = creds.method(:dig)

    creds.stub(:tiktok, tiktok) do
      # Only intercept :tiktok lookups; everything else keeps working so this
      # doesn't disturb unrelated credential reads inside the block.
      creds.stub(:dig, ->(*keys) {
        keys.first == :tiktok ? tiktok.dig(*keys[1..]) : original_dig.call(*keys)
      }, &block)
    end
  end
end
