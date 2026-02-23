# frozen_string_literal: true

class User < ApplicationRecord
  has_many :connected_drives, dependent: :destroy
  has_many :planned_posts, dependent: :destroy
  has_many :social_templates, dependent: :nullify

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
end
