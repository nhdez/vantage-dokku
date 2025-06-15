class AddServerInfoToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :os_version, :string
    add_column :servers, :ram_total, :string
    add_column :servers, :cpu_model, :string
    add_column :servers, :cpu_cores, :integer
    add_column :servers, :disk_total, :string
    add_column :servers, :last_connected_at, :datetime
    add_column :servers, :connection_status, :string, default: 'unknown'
    
    add_index :servers, :connection_status
    add_index :servers, :last_connected_at
  end
end
