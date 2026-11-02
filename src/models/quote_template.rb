class App::Models::QuoteTemplate < Sequel::Model(:quote_templates)
  # A saved package, e.g. "Modular kitchen hardware set": items [{ product_id, quantity, brand_id? }]
  def validate
    super
    validates_presence [:name]
    errors.add(:items, "can't be empty") if items.to_a.empty?
  end

  # for the website: only products that are on sale, with brands that make them
  def as_catalog(products, brand_ids)
    lines = items.to_a.filter_map do |i|
      product = products[i['product_id']]
      next unless product
      brand = i['brand_id'] if i['brand_id'] && brand_ids.include?(i['brand_id']) && product.brand_ids.to_a.include?(i['brand_id'])
      { productId: product.id, quantity: i['quantity'].to_i.clamp(1, 100_000), brandId: brand }.compact
    end
    { id: id, name: name, description: description, items: lines }
  end
end
