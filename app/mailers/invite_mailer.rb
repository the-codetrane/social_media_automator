class InviteMailer < ApplicationMailer
  def invite(user)
    @user = user
    mail subject: "You've been invited to Social Media Automator", to: user.email_address
  end
end
