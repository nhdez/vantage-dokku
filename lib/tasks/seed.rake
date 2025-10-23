# Custom seed tasks for loading specific seed files
namespace :db do
  namespace :seed do
    desc "Load application settings seeds"
    task app_settings: :environment do
      load(Rails.root.join('db', 'seeds', 'app_settings.rb'))
    end
  end
end
