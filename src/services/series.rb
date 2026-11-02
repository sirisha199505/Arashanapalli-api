class App::Services::Series < App::Services::Base
  def model; BrandSeries; end

  def self.fields
    {
      save: [:brand_id, :name, :description, :position, :active]
    }
  end

  def list
    ds = model.order(:brand_id, :position, :name)
    ds = ds.where(brand_id: qs[:brand_id]) if qs[:brand_id].present?
    return_success(ds.all.map(&:to_pos))
  end

  # removing a series also takes it off its products
  def delete
    id = item.id
    App.db.transaction do
      Product.where(Sequel.pg_array(:series_ids).contains(Sequel.pg_array([id], :integer)))
             .update(series_ids: Sequel.function(:array_remove, :series_ids, id))
      super
    end
  end
end
