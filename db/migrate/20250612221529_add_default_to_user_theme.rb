class AddDefaultToUserTheme < ActiveRecord::Migration[8.0]
  def change
    change_column_default :users, :theme, 'auto'
    
    # Update existing users without a theme preference
    User.where(theme: nil).update_all(theme: 'auto')
  end
end
