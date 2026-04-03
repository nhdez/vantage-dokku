class CreateKamalRegistries < ActiveRecord::Migration[8.0]
  def change
    create_table :kamal_registries do |t|
      t.references :kamal_configuration, null: false, foreign_key: true, index: { unique: true }

      t.string :registry_server, default: "ghcr.io"
      t.string :username
      t.string :password

      t.timestamps
    end
  end
end
