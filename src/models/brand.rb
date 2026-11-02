class App::Models::Brand < Sequel::Model
  unrestrict_primary_key

  # 'Door Hinges' → 'door-hinges'; a number is added if the id is taken
  def self.slug_for(name)
    base = name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    return base if base.empty? || self[base].nil?
    (2..).each { |n| return "#{base}-#{n}" if self["#{base}-#{n}"].nil? }
  end

  one_to_many :series, class: 'App::Models::BrandSeries', key: :brand_id, order: [:position, :name]

  # A short code for the brand ('HET'): a product's dynamic code is its code plus this, e.g. AT1002-HET
  def self.normalize_code(input)
    input.to_s.upcase.gsub(/[^A-Z0-9]/, '')
  end

  # First three letters of the name, with a number added if that code is taken
  def self.code_for(name)
    base = normalize_code(name).gsub(/\d/, '')[0, 3].presence || 'BR'
    return base unless where(code: base).any?
    (2..).each { |n| return "#{base}#{n}" unless where(code: "#{base}#{n}").any? }
  end

  def before_validation
    self.code = code.present? ? self.class.normalize_code(code) : self.class.code_for(name)
    super
  end

  def validate
    super
    validates_presence [:id, :name, :price_factor, :code]
    validates_unique :id
    validates_unique :code, message: 'is already used by another brand'
    validates_format(/\A[A-Z0-9]{2,5}\z/, :code, message: 'must be 2–5 letters or digits')
  end

  # Shape the frontend catalog expects; `series` = this brand's visible series
  def as_catalog(series = [])
    {
      id: id, name: name, code: code, tier: tier, priceFactor: price_factor.to_f, specs: specs.to_h,
      series: series.map { |s| { id: s.id, name: s.name, description: s.description } }
    }
  end
end
