class CreateLinkedAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :linked_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :account_username
      t.string :account_email
      t.text :access_token, null: false
      t.text :refresh_token
      t.datetime :token_expires_at
      t.boolean :active, default: true, null: false
      t.text :metadata

      t.timestamps
    end
    
    add_index :linked_accounts, [:user_id, :provider], unique: true
    add_index :linked_accounts, :provider
    add_index :linked_accounts, :active
  end
end
