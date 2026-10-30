class App::Services::Brands < App::Services::Base
  def model; Brand; end

  def self.fields
    {
      save: [:id, :name, :tier, :price_factor, { specs: {} }, :position, :active]
    }
  end

  def list
    return_success(model.order(:position, :name).all.map(&:to_pos))
  end
end
