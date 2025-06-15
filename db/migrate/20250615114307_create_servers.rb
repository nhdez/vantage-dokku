class CreateServers < ActiveRecord::Migration[8.0]
  def change
    create_table :servers do |t|
      t.string :name, null: false
      t.string :ip, null: false
      t.string :username, default: 'root'
      t.string :internal_ip
      t.integer :port, default: 22
      t.string :service_provider
      t.string :uuid, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :servers, :uuid, unique: true
    add_index :servers, [:user_id, :name]
  end
end
