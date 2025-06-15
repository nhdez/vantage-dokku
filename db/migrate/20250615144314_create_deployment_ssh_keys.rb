class CreateDeploymentSshKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :deployment_ssh_keys do |t|
      t.references :deployment, null: false, foreign_key: true
      t.references :ssh_key, null: false, foreign_key: true

      t.timestamps
    end
    
    add_index :deployment_ssh_keys, [:deployment_id, :ssh_key_id], unique: true
  end
end
