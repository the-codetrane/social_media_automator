# The card on each admin connect page (Instagram, YouTube, TikTok): the platform's logo and
# name, whether it's connected and to which account, optional details, then the actions
# (the block).
#
#   <%= render IntegrationCardComponent.new(name: "YouTube Channel", connected: @connected, account: @channel_title) do |card| %>
#     <% card.with_logo { image_tag "youtube.svg", alt: "" } %>
#     <%= ui_button "Connect YouTube channel", href: @auth_url %>
#   <% end %>
class IntegrationCardComponent < ViewComponent::Base
  include ComponentLibrary2100::Helpers
  include ThemeHelper

  renders_one :logo
  renders_one :details

  def initialize(name:, connected:, account: nil)
    @name = name
    @connected = connected
    @account = account.presence
  end

  def status
    @connected ? "Connected" : "Not connected"
  end

  def status_variant
    @connected ? :success : :secondary
  end
end
