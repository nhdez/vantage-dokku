class CreateKamalAccessories < ActiveRecord::Migration[8.0]
  def change
    create_table :kamal_accessories do |t|
      t.references :kamal_configuration, null: false, foreign_key: true

      t.string :name, null: false
      t.string :image, null: false
      t.string :host
      t.integer :port
      t.jsonb :env_vars, default: {}
      t.jsonb :volumes, default: []
      t.string :status, default: "pending"

      t.timestamps
    end

    add_index :kamal_accessories, [ :kamal_configuration_id, :name ], unique: true
  end
end
