class AddDockerInfoToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :docker_version, :string
    add_column :servers, :docker_checked_at, :datetime
  end
end
