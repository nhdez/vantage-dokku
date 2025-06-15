class CreateDomains < ActiveRecord::Migration[8.0]
  def change
    create_table :domains do |t|
      t.references :deployment, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :ssl_enabled, default: false, null: false
      t.boolean :default_domain, default: false, null: false
      t.text :ssl_error_message
      t.datetime :ssl_configured_at

      t.timestamps
    end
    
    add_index :domains, [:deployment_id, :name], unique: true
    add_index :domains, [:deployment_id, :default_domain]
  end
end
