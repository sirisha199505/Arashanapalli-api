begin
  require 'dotenv/load' # loads .env in development
rescue LoadError
end
require 'bundler'
require 'open-uri'
require 'csv'
Rack::Utils # Patch
require './src/app'

Bundler.require(:default, App.env)


use Rack::Cors do

  allow do
    origins '*'
    resource '*', :headers => :any, :methods => [:get, :post, :delete, :put, :patch, :options, :head]
  end
end

App.load!

run App::Routes

if App.development?
  Listen.to(File.expand_path(File.dirname(__FILE__)), only: %r{.rb$}) do |added, modified, removed|
    files_to_reload = added + modified
    
    App.logger.info("Reloading: #{files_to_reload.join(', ')}")
    
    # Handle route file specially to ensure proper reloading
    if files_to_reload.any? { |f| f.include?('routes.rb') }
      App.logger.info("Routes file changed, consider restarting the server for full effect")
      # Optionally implement more sophisticated routes reloading here
    end
    
    # Reload all changed files
    files_to_reload.each do |f|
      begin
        load(f)
        App.logger.info("Successfully reloaded: #{f}")
      rescue => e
        App.logger.error("Error reloading #{f}: #{e.message}")
        App.logger.error(e.backtrace.join("\n"))
      end
    end
  end.start
end
