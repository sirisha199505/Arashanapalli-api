class App::Services::Brands < App::Services::Base
  def model; Brand; end

  def self.fields
    {
      save: [:id, :name, :tier, :price_factor, { specs: {} }, :position, :active]
    }
  end

  def create
    data = data_for(:save)
    data['id'] = data['id'].presence || model.slug_for(data['name'])
    save(model.new(data))
  end

  def update
    super(data_for(:save).except('id'))
  end

  def list
    return_success(model.order(:position, :name).all.map(&:to_pos))
  end
end
