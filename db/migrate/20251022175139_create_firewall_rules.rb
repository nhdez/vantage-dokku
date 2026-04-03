class CreateFirewallRules < ActiveRecord::Migration[8.0]
  def change
    create_table :firewall_rules do |t|
      t.references :server, null: false, foreign_key: true
      t.string :action, null: false, default: 'allow'
      t.string :direction, null: false, default: 'in'
      t.string :port
      t.string :protocol, default: 'tcp'
      t.string :from_ip
      t.string :to_ip
      t.string :comment
      t.integer :position
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :firewall_rules, [ :server_id, :position ]
  end
end
