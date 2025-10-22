class CreatePortMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :port_mappings do |t|
      t.references :deployment, null: false, foreign_key: true
      t.string :scheme, null: false
      t.integer :host_port, null: false
      t.integer :container_port, null: false

      t.timestamps
    end

    add_index :port_mappings, [:deployment_id, :scheme, :host_port, :container_port],
              unique: true,
              name: 'index_port_mappings_on_deployment_and_mapping'
  end
end
