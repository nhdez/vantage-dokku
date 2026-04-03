class CreateKamalConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :kamal_configurations do |t|
      t.references :deployment, null: false, foreign_key: true, index: { unique: true }

      # App identity
      t.string :service_name
      t.string :image

      # Builder
      t.string :builder_arch, default: "local"
      t.string :builder_remote

      # App config
      t.string :asset_path
      t.string :healthcheck_path, default: "/up"
      t.integer :healthcheck_port

      # kamal-proxy settings
      t.string :proxy_host
      t.boolean :proxy_ssl, default: true
      t.integer :proxy_app_port, default: 3000
      t.integer :proxy_response_timeout, default: 30
      t.boolean :proxy_buffering, default: false
      t.string :proxy_max_body_size
      t.boolean :proxy_forward_headers, default: true

      # Status
      t.boolean :configured, default: false
      t.text :error_message

      t.timestamps
    end
  end
end
