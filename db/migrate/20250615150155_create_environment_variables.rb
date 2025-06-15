class CreateEnvironmentVariables < ActiveRecord::Migration[8.0]
  def change
    create_table :environment_variables do |t|
      t.references :deployment, null: false, foreign_key: true
      t.string :key, null: false
      t.text :value
      t.string :description

      t.timestamps
    end
    
    add_index :environment_variables, [:deployment_id, :key], unique: true
  end
end
