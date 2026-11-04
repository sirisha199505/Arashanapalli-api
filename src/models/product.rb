class App::Models::Product < Sequel::Model
  unrestrict_primary_key

  # 'Door Hinges' → 'door-hinges'; a number is added if the id is taken
  def self.slug_for(name)
    base = name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    return base if base.empty? || self[base].nil?
    (2..).each { |n| return "#{base}-#{n}" if self["#{base}-#{n}"].nil? }
  end

  CODE_PREFIX = 'AT'

  # What the sales team types → stored form: '1001', 'at-1001', 'AT 1001' → 'AT1001'
  def self.normalize_code(input)
    code = input.to_s.upcase.gsub(/[^A-Z0-9]/, '')
    code.match?(/\A\d+\z/) ? "#{CODE_PREFIX}#{code}" : code
  end

  # The next free shelf code after the highest AT number in use
  def self.next_code
    last = db[:products].where(Sequel.like(:code, "#{CODE_PREFIX}%")).select_map(:code).map { |c| c.delete_prefix(CODE_PREFIX).to_i }.max
    "#{CODE_PREFIX}#{[last || 1000, 1000].max + 1}"
  end

  # Gives every product without a code the next free one (used after seeding)
  def self.assign_missing_codes!
    where(code: nil).order(:position, :id).each { |p| p.update(code: next_code) }
  end

  def before_validation
    self.code = code.present? ? self.class.normalize_code(code) : self.class.next_code
    # a product can only be in a series of a brand that makes it
    if series_ids.to_a.any?
      valid = App::Models::BrandSeries.where(id: series_ids.to_a.map(&:to_i), brand_id: brand_ids.to_a).select_map(:id)
      self.series_ids = Sequel.pg_array(valid, :integer)
    end
    super
  end

  def validate
    super
    validates_presence [:id, :name, :category, :unit, :base_price, :code]
    validates_unique :id
    validates_unique :code, message: 'is already used by another product'
    validates_integer :base_price
  end

  # The price of this product in a brand: the brand's own price if one is set, else base price × brand factor
  def price_for(brand, details = nil)
    details&.price || standard_price(brand)
  end

  def standard_price(brand)
    (base_price * brand.price_factor.to_f).round
  end

  # Shape the frontend catalog expects
  def as_catalog
    {
      id: id, name: name, category: category, subcategory: self[:subcategory].presence, image: image, description: description,
      unit: unit, basePrice: base_price, brandIds: brand_ids.to_a, mock: mock,
      code: code, newArrival: new_arrival, seriesIds: series_ids.to_a, spec: specification
    }.compact
  end
end
