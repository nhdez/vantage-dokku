class CreateDatabaseConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :database_configurations do |t|
      t.references :deployment, null: false, foreign_key: true, index: { unique: true }
      t.string :database_type, null: false
      t.string :database_name, null: false
      t.string :username
      t.string :password
      t.boolean :redis_enabled, default: false, null: false
      t.string :redis_name
      t.boolean :configured, default: false, null: false
      t.text :configuration_output
      t.text :error_message

      t.timestamps
    end
    
    add_index :database_configurations, :database_name, unique: true
  end
end
