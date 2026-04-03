class AddSelfHostedToKamalRegistries < ActiveRecord::Migration[8.0]
  def change
    add_column :kamal_registries, :self_hosted, :boolean, default: false, null: false
  end
end
