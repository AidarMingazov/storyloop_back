class AddTokenToSessions < ActiveRecord::Migration[8.1]
  # Bearer token for API clients (native apps); web sessions keep using the signed cookie.
  def change
    add_column :sessions, :token, :string
    add_index :sessions, :token, unique: true
  end
end
