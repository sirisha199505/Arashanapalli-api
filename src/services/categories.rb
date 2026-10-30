class App::Services::Categories < App::Services::Base
  def model; Category; end

  def self.fields
    {
      save: [:name, :icon, :position, :active]
    }
  end

  def list
    counts = Product.group_and_count(:category).to_hash(:category, :count)
    return_success(model.order(:position, :name).all.map { |c| c.to_pos.merge('product_count' => counts[c.name] || 0) })
  end

  # Products store the category name, so a rename is applied to them in the same transaction
  def update
    data = data_for(:save)
    old_name = item.name
    App.db.transaction do
      item.set_fields(data, data.keys)
      save(item) do |c|
        Product.where(category: old_name).update(category: c.name) if c.name != old_name
        return_success(c.to_pos)
      end
    end
  end

  def delete
    used = Product.where(category: item.name).count
    return_errors!("#{used} products use this category — move them to another category first") if used.positive?
    super
  end
end
