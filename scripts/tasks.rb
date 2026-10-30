require 'thor'
require 'active_support/all'

MODEL_CODE =  -> (model) {
%Q{
class App::Models::#{model.classify} < Sequel::Model
  def validate
    super
    # validates_presence \[:name, :date\]
    # validates_unique :email
    # validates_includes ROLES, :role
  end
end
}}

class Tasks < Thor

  desc "create_models", "one, two"
  def create_models(models)
    root = File.dirname(__FILE__)

    dir = File.join(root, '..', 'src/models')
    models = models.split(',').map(&:strip)

    models.each do |model|
      path = File.join(dir,"#{model}.rb")
      puts path
      unless File.exist?(path)
        File.open(path, 'w+') do |f|
          f << MODEL_CODE.(model)
        end
      end
    end
  end

end

Tasks.start(ARGV)