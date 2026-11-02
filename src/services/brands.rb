class App::Services::Brands < App::Services::Base
  def model; Brand; end

  def self.fields
    {
      save: [:id, :name, :code, :tier, :price_factor, { specs: {} }, :position, :active]
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

  # each brand with its series (all of them, hidden ones too) for the admin
  def list
    series = BrandSeries.order(:position, :name).all.group_by(&:brand_id)
    return_success(model.order(:position, :name).all.map { |b| b.to_pos.merge('series' => (series[b.id] || []).map(&:to_pos)) })
  end
end
