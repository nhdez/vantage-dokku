class AddThemeToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :theme, :string, default: 'auto'
    add_index :users, :theme
  end
end
