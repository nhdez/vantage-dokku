class CreateApplicationHealths < ActiveRecord::Migration[8.0]
  def change
    create_table :application_healths do |t|
      t.references :deployment, null: false, foreign_key: true
      t.integer :response_code
      t.float :response_time
      t.string :status
      t.datetime :checked_at
      t.text :response_body

      t.timestamps
    end
    
    add_index :application_healths, [:deployment_id, :checked_at]
    add_index :application_healths, :checked_at
  end
end
