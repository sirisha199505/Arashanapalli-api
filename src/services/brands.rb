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
    save(model.new(data)) do |record|
      Audit.log(:brand, record.id, :created, ref: record.code, note: record.name)
      return_success(record.to_pos)
    end
  end

  def update
    data = data_for(:save).except('id')
    item.set_fields(data, data.keys)
    item.valid?
    changes = Audit.changes_of(item)
    save(item) do |record|
      Audit.log(:brand, record.id, :updated, ref: record.code, changes: changes, note: record.name) if changes.any?
      return_success(record.to_pos)
    end
  end

  # hide (it stays on old quotations)
  def remove
    item.active = false
    save(item) do |record|
      Audit.log(:brand, record.id, :hidden, ref: record.code, note: record.name)
      return_success(record.to_pos)
    end
  end

  # each brand with its series (all of them, hidden ones too) for the admin
  def list
    series = BrandSeries.order(:position, :name).all.group_by(&:brand_id)
    return_success(model.order(:position, :name).all.map { |b| b.to_pos.merge('series' => (series[b.id] || []).map(&:to_pos)) })
  end
end
