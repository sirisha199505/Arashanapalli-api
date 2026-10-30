class App::Models::Brand < Sequel::Model
  unrestrict_primary_key

  # 'Door Hinges' → 'door-hinges'; a number is added if the id is taken
  def self.slug_for(name)
    base = name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    return base if base.empty? || self[base].nil?
    (2..).each { |n| return "#{base}-#{n}" if self["#{base}-#{n}"].nil? }
  end

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
