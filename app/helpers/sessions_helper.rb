# frozen_string_literal: true

module SessionsHelper
  BROWSERS = [
    [ /Edg(?:e|A|iOS)?\//, "Edge" ],
    [ /OPR\/|Opera/, "Opera" ],
    [ /Firefox\/|FxiOS\//, "Firefox" ],
    [ /Chrome\/|CriOS\//, "Chrome" ],
    [ /Safari\//, "Safari" ]
  ].freeze

  SYSTEMS = [
    [ /iPhone|iPad|iPod/, "iOS" ],
    [ /Android/, "Android" ],
    [ /Windows/, "Windows" ],
    [ /Mac OS X|Macintosh/, "macOS" ],
    [ /CrOS/, "ChromeOS" ],
    [ /Linux/, "Linux" ]
  ].freeze

  # Turns a User-Agent string into a short label such as "Chrome on macOS".
  # Falls back to the truncated raw string when the browser or system is unknown.
  def device_label(user_agent, length: 40)
    ua = user_agent.to_s.strip
    return "Unknown device" if ua.empty?

    browser = BROWSERS.find { |pattern, _| ua.match?(pattern) }&.last
    system = SYSTEMS.find { |pattern, _| ua.match?(pattern) }&.last

    if browser && system
      "#{browser} on #{system}"
    else
      ua.truncate(length)
    end
  end
end
