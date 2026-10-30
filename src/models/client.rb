class App::Models::Client < Sequel::Model
  # Associations
  # one_to_many :properties
  # one_to_many :users

  def validate
    super
    validates_presence [:name]
    validates_unique :email
  end

  def as_pos
    as_json(only: [:id, :name, :email, :active, :created_at, :updated_at])
  end
end
