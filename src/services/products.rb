class App::Services::Products < App::Services::Base
  def model; Product; end

  def self.fields
    {
      save: [:id, :name, :category, :image, :description, :unit, :base_price, { brand_ids: {} }, :mock, :position, :active, :code, :new_arrival, { series_ids: {} },
             :sku, :specification, :hsn_code, :gst_rate, :subcategory]
    }
  end

  def create
    data = data_for(:save)
    data['id'] = data['id'].presence || model.slug_for(data['name'])
    save(model.new(data)) do |record|
      Audit.log(:product, record.id, :created, ref: record.code, note: record.name)
      return_success(record.to_pos)
    end
  end

  def update
    data = data_for(:save).except('id')
    item.set_fields(data, data.keys)
    item.valid?
    changes = Audit.changes_of(item)
    save(item) do |record|
      Audit.log(:product, record.id, :updated, ref: record.code, changes: changes, note: record.name) if changes.any?
      return_success(record.to_pos)
    end
  end

  # hide (it stays on old quotations)
  def remove
    item.active = false
    save(item) do |record|
      Audit.log(:product, record.id, :hidden, ref: record.code, note: record.name)
      return_success(record.to_pos)
    end
  end

  def list
    ds = model.order(:position, :name)
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    if qs[:search].present?
      ds = ds.where(Sequel.ilike(:name, "%#{qs[:search]}%") | { code: Product.normalize_code(qs[:search]) })
    end
    ds = ds.where(new_arrival: true) if qs[:new_arrival] == 'true'
    count = ds.count
    return_success(ds.offset(offset).limit(limit).all.map(&:to_pos), total_pages: (count / page_size.to_f).ceil)
  end
end
