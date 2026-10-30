begin
  require 'dotenv/load' # loads .env in development
rescue LoadError
end
require './src/app'
namespace :db do
  desc "Run migrations"
  task :migrate, [:version] do |t, args|
    puts args, App.db_url
    require "sequel/core"
    Sequel.extension :migration
    version = args[:version].to_i if args[:version]
    puts version
    Sequel.connect(App.db_url) do |db|
      db.extension :pg_enum
      Sequel::Migrator.run(db, "src/migrations", target: version)
    end
  end
end


require 'optparse'


namespace :create do
  desc "Creates Model"
  task :models do
    models = []
    OptionParser.new do |opts|
      opts.banner = "Usage: rake create:models [options]"
      opts.on("-n", "--names ARG", String) { |str| models += str.split(',') }
    end.parse!
    puts models
    exit
  end
end

# Usage: DB_URL="your-database-url" rake db:migrate
# To rollback: DB_URL="your-database-url" rake db:migrate[0]
# Loads the full app (gems, models) for tasks that need it
def boot_app!
  require 'bundler'
  require 'securerandom'
  Bundler.require(:default, App.env)
  App.load!
end

namespace :db do
  desc "Seed categories, brands and products from src/seeds/ (skips ids that already exist, so admin edits are kept)"
  task :seed do
    boot_app!
    data = JSON.parse(File.read(File.join(App.root, 'src/seeds/catalog.json')))
    db = App.db
    categories = JSON.parse(File.read(File.join(App.root, 'src/seeds/categories.json')))
    db.transaction do
      db[:categories].insert_conflict.multi_insert(categories)
      db[:brands].insert_conflict.multi_insert(
        data['brands'].map { |b| b.merge('specs' => Sequel.pg_jsonb(b['specs'])) }
      )
      db[:products].insert_conflict.multi_insert(
        data['products'].map { |p| p.merge('brand_ids' => Sequel.pg_array(p['brand_ids'], :text)) }
      )
    end
    puts "categories: #{db[:categories].count}, brands: #{db[:brands].count}, products: #{db[:products].count}"
  end
end

namespace :users do
  desc "Create an admin user: rake users:create_admin EMAIL=you@example.com NAME='Your Name' [PASSWORD=...]"
  task :create_admin do
    boot_app!
    email = ENV.fetch('EMAIL') { abort 'EMAIL is required' }
    password = ENV['PASSWORD'].presence || SecureRandom.base64(12)
    user = App::Models::User.new(full_name: ENV.fetch('NAME', 'Admin'), email: email, role: App::Models::User::ROLES[:admin])
    user.password = password
    abort "Could not create user: #{user.errors.full_messages.join(', ')}" unless user.save
    puts "Admin created: #{email}"
    puts "Password: #{password}" unless ENV['PASSWORD'].present?
  end
end
