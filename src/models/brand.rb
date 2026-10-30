class App::Models::Brand < Sequel::Model
  unrestrict_primary_key

  def validate
    super
    validates_presence [:id, :name, :price_factor]
    validates_unique :id
  end

  # Shape the frontend catalog expects
  def as_catalog
    { id: id, name: name, tier: tier, priceFactor: price_factor.to_f, specs: specs.to_h }
  end
end
