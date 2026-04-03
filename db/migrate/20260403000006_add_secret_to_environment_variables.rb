class AddSecretToEnvironmentVariables < ActiveRecord::Migration[8.0]
  def change
    add_column :environment_variables, :secret, :boolean, default: false, null: false
  end
end
