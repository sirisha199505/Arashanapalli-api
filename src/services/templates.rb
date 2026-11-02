class App::Services::Templates < App::Services::Base
  # Saved packages / template quotes ("Modular kitchen hardware set"): any staff can use them; Admin and Sales manage them
  def model; QuoteTemplate; end

  def self.fields
    {
      save: [:name, :description, { items: {} }, :public, :active, :position]
    }
  end

  def list
    return_success(model.order(:position, :name).all.map(&:to_pos))
  end

  def create
    can_manage!
    save(model.new(clean(data_for(:save))))
  end

  def update
    can_manage!
    data = clean(data_for(:save))
    item.set_fields(data, data.keys)
    save(item)
  end

  def delete
    can_manage!
    super
  end

  private

  def can_manage!
    return_errors!('Only Admin or Sales can change packages', 403) if App.cu.user_obj.limited?
  end

  # keep only products that exist, with a sensible quantity and (optionally) a brand that makes them
  def clean(data)
    return data unless data.key?('items')
    raw = data['items'].is_a?(Array) ? data['items'] : []
    products = Product.where(id: raw.map { |i| i['product_id'].to_s }).to_hash(:id)
    data['items'] = raw.filter_map do |i|
      product = products[i['product_id'].to_s] or next
      quantity = Integer(i['quantity'].to_s, exception: false)&.clamp(1, 100_000) || 1
      brand = i['brand_id'].to_s if product.brand_ids.to_a.include?(i['brand_id'].to_s)
      { 'product_id' => product.id, 'quantity' => quantity, 'brand_id' => brand }.compact
    end
    data
  end
end
