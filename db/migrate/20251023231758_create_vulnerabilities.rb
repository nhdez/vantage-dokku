class CreateVulnerabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :vulnerabilities do |t|
      t.references :vulnerability_scan, null: false, foreign_key: true
      t.string :osv_id, null: false
      t.decimal :cvss_score, precision: 3, scale: 1
      t.string :ecosystem, null: false
      t.string :package_name, null: false
      t.string :current_version, null: false
      t.string :fixed_version
      t.string :severity, null: false
      t.string :source_file
      t.string :osv_url

      t.timestamps
    end

    add_index :vulnerabilities, :osv_id
    add_index :vulnerabilities, :severity
  end
end
