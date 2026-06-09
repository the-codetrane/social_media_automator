Geocoder.configure(
  lookup: :nominatim,
  timeout: 5,
  cache: Rails.cache,
  http_headers: {
    "User-Agent" => "SocialMediaAutomator/1.0 (michael.m.cain.ii@gmail.com)"
  }
)
