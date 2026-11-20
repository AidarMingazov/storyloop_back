class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # Guests (reading before sign-up) have no email or password yet.
      t.string :email_address
      t.string :password_digest
      t.boolean :guest, null: false, default: false
      t.boolean :admin, null: false, default: false

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
