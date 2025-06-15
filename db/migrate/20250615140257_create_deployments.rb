class CreateDeployments < ActiveRecord::Migration[8.0]
  def change
    create_table :deployments do |t|
      t.string :name, null: false
      t.string :dokku_app_name, null: false
      t.text :description
      t.references :server, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    
    add_index :deployments, [:user_id, :name], unique: true
    add_index :deployments, :dokku_app_name, unique: true
    add_index :deployments, [:server_id, :dokku_app_name], unique: true
  end
end
