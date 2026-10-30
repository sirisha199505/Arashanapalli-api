class App::Services::Products < App::Services::Base
  def model; Product; end

  def self.fields
    {
      save: [:id, :name, :category, :image, :description, :unit, :base_price, { brand_ids: {} }, :mock, :position, :active]
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
    ds = model.order(:position, :name)
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    ds = ds.where(Sequel.ilike(:name, "%#{qs[:search]}%")) if qs[:search].present?
    count = ds.count
    return_success(ds.offset(offset).limit(limit).all.map(&:to_pos), total_pages: (count / page_size.to_f).ceil)
  end
end
