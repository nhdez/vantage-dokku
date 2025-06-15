class AddUuidToDeployments < ActiveRecord::Migration[8.0]
  def change
    add_column :deployments, :uuid, :string
    
    # Generate UUIDs for existing deployments
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE deployments SET uuid = gen_random_uuid()::text WHERE uuid IS NULL;
        SQL
      end
    end
    
    change_column_null :deployments, :uuid, false
    add_index :deployments, :uuid, unique: true
  end
end
