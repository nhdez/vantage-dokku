class CreateSshKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :ssh_keys do |t|
      t.string :name, null: false
      t.text :public_key, null: false
      t.datetime :expires_at
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    
    add_index :ssh_keys, [:user_id, :name], unique: true
  end
end
