class AddPasswordToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :password, :string
  end
end
