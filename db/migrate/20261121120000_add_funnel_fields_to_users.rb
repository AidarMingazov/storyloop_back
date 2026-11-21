class AddFunnelFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    # One analytics id from the first anonymous visit through guest reading to a registered account.
    add_column :users, :analytics_id, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_index :users, :analytics_id, unique: true
    # Changes on every magic-link sign-in, so each emailed link works once.
    add_column :users, :magic_login_at, :datetime
  end
end
