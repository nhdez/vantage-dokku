class AddUfwStatusToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :ufw_enabled, :boolean, default: false
    add_column :servers, :ufw_status, :string
  end
end
