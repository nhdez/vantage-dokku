class CreateOauthSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_settings do |t|
      t.string :key, null: false
      t.text :value
      t.text :description
      t.boolean :enabled, default: false

      t.timestamps
    end
    
    add_index :oauth_settings, :key, unique: true
  end
end
