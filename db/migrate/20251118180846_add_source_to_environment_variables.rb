class AddSourceToEnvironmentVariables < ActiveRecord::Migration[8.0]
  def change
    add_column :environment_variables, :source, :string, default: 'user', null: false
    add_index :environment_variables, :source
  end
end
