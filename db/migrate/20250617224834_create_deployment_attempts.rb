class CreateDeploymentAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :deployment_attempts do |t|
      t.references :deployment, null: false, foreign_key: true
      t.string :status, null: false, default: 'pending'
      t.text :logs
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.integer :attempt_number, null: false, default: 1

      t.timestamps
    end
    
    add_index :deployment_attempts, [:deployment_id, :attempt_number], unique: true
    add_index :deployment_attempts, :status
  end
end
