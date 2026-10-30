class App::Models::Product < Sequel::Model
  unrestrict_primary_key

  def validate
    super
    validates_presence [:id, :name, :category, :unit, :base_price]
    validates_unique :id
    validates_integer :base_price
  end

  # Shape the frontend catalog expects
  def as_catalog
    {
      id: id, name: name, category: category, image: image, description: description,
      unit: unit, basePrice: base_price, brandIds: brand_ids.to_a, mock: mock
    }
  end
end
