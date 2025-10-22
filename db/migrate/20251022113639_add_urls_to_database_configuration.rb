class AddUrlsToDatabaseConfiguration < ActiveRecord::Migration[8.0]
  def change
    add_column :database_configurations, :database_url, :text
    add_column :database_configurations, :redis_url, :text
  end
end
