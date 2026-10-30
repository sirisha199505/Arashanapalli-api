class App::Models::Category < Sequel::Model
  def validate
    super
    validates_presence [:name]
    validates_unique :name
  end

  # Shape the frontend catalog expects
  def as_catalog
    { name: name, icon: icon }
  end
end
