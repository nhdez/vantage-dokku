class AddDokkuVersionToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :dokku_version, :string
  end
end
