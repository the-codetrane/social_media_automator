module ApplicationHelper
  def decode_name(name)
    return name if name.blank?
    CGI.unescape(name)
  end
end
