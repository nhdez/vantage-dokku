class CreateActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.text :details
      t.string :ip_address
      t.text :user_agent
      t.datetime :occurred_at, null: false
      t.string :controller_name
      t.string :action_name
      t.text :params_data

      t.timestamps
    end
    
    add_index :activity_logs, [:user_id, :occurred_at]
    add_index :activity_logs, :action
    add_index :activity_logs, :occurred_at
  end
end
