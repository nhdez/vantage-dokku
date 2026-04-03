class CreateKamalServers < ActiveRecord::Migration[8.0]
  def change
    create_table :kamal_servers do |t|
      t.references :kamal_configuration, null: false, foreign_key: true
      t.references :server, null: false, foreign_key: true

      t.string :role, default: "web"
      t.boolean :primary, default: false
      t.string :cmd
      t.integer :stop_wait_time
      t.jsonb :docker_options, default: {}

      t.timestamps
    end

    add_index :kamal_servers, [ :kamal_configuration_id, :server_id, :role ], unique: true,
      name: "index_kamal_servers_on_config_server_role"
  end
end
