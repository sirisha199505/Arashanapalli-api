class App::Models::BrandSeries < Sequel::Model(:brand_series)
  # The "individual" level of a brand: class = tier (Premium…), sub-class = brand (Hettich), individual = series (InnoTech)
  many_to_one :brand, class: 'App::Models::Brand'

  def validate
    super
    validates_presence [:brand_id, :name]
    taken = self.class.where(brand_id: brand_id, name: name).exclude(id: id).any?
    errors.add(:name, 'already exists for this brand') if taken
  end
end
