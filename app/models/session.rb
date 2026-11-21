class Session < ApplicationRecord
  belongs_to :user
  has_secure_token :token # API bearer token (web uses the signed session cookie)
end
