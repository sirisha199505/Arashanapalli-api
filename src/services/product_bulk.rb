class App::Services::ProductBulk < App::Services::Base
  # Admin bulk updates, a page at a time: e.g. all 100 Godrej products — price, stock, photo, description —
  # or product details (name, base price, unit, photo, description, new arrival, shown) across brands.
  # A save is all or nothing, and every changed product gets an audit entry; one save shares one batch ID.

  PRODUCT_FIELDS = %w[name base_price unit image description new_arrival active].freeze
  BRAND_FIELDS = %w[price stock_status stock_qty image description].freeze
  # how a brand's change is named in the audit trail: "Godrej price: 122 → 130"
  BRAND_LABELS = { 'price' => 'price', 'stock_status' => 'stock', 'stock_qty' => 'stock qty', 'image' => 'photo', 'description' => 'description' }.freeze
  MAX_ROWS = 300

  # filters: brand_id (that brand's products, with its details), category, search (name / code), status (shown / hidden)
  def list
    ds = Product.dataset
    ds = ds.where(Sequel.lit('? = ANY(brand_ids)', brand.id)) if brand
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    if qs[:search].present?
      ds = ds.where(Sequel.ilike(:name, "%#{qs[:search].strip}%") | { code: Product.normalize_code(qs[:search]) })
    end
    ds = ds.where(active: qs[:status] == 'shown') if %w[shown hidden].include?(qs[:status])
    count = ds.count
    products = ds.order(:position, :name).offset(offset).limit(limit).all
    details = brand ? ProductBrand.where(brand_id: brand.id, product_id: products.map(&:id)).to_hash(:product_id) : {}
    return_success(products.map { |p| row(p, details[p.id]) }, total_pages: (count / page_size.to_f).ceil, total: count)
  end

  # data: { brand_id?, rows: [{ id, product: { name, base_price, … }, brand: { price, stock_status, … } }] }
  # → { updated, unchanged, batch_id }, or every row's errors (nothing is saved then)
  def update
    rows = params[:rows]
    return_errors!('Nothing to save') unless rows.is_a?(Array) && rows.any?
    return_errors!("Save at most #{MAX_ROWS} products at a time") if rows.size > MAX_ROWS
    return_errors!('Choose a brand to change brand prices or stock') if rows.any? { |r| r[:brand].present? } && !brand
    return_errors!('Each product can only be in a save once') if rows.map { |r| r[:id].to_s }.uniq.size < rows.size

    products = Product.where(id: rows.map { |r| r[:id].to_s }).to_hash(:id)
    details = brand ? ProductBrand.where(brand_id: brand.id, product_id: products.keys).to_hash(:product_id) : {}
    errors = {}
    staged = rows.filter_map do |r|
      product = products[r[:id].to_s]
      next errors[r[:id].to_s] = ['No such product'] unless product
      next errors[product.id] = ["#{brand.name} doesn't make this product"] if r[:brand].present? && !product.brand_ids.to_a.include?(brand.id)

      stage(product, r, details[product.id], errors)
    end
    return_errors!({ rows: errors }, 422) if errors.any?

    batch_id = SecureRandom.hex(6)
    changed = staged.select { |s| s[:changes].any? }
    Product.db.transaction do
      changed.each do |s|
        s[:product].save(raise_on_failure: true) if s[:product].modified?
        if (d = s[:details])
          d.blank? ? (d.delete unless d.new?) : d.save(raise_on_failure: true)
        end
        Audit.log(:product, s[:product].id, :bulk_updated, ref: s[:product].code, changes: s[:changes], batch_id: batch_id,
                                                           note: "#{s[:product].name}#{" · #{brand.name}" if s[:details]}")
      end
    end
    return_success({ updated: changed.size, unchanged: staged.size - changed.size, batch_id: (batch_id if changed.any?) })
  rescue Sequel::ValidationFailed, Sequel::DatabaseError => e
    return_errors!(e.message)
  end

  private

  def brand
    return @brand if defined?(@brand)

    id = (params && params[:brand_id]).presence || qs[:brand_id].presence
    @brand = id && (Brand[id.to_s] || return_errors!('No such brand', 404))
  end

  def row(product, details)
    shown = product.values.slice(:id, :code, :name, :category, :unit, :base_price, :image, :description, :new_arrival, :active)
    return shown unless brand

    shown.merge(brand: {
      dynamic_code: "#{product.code}-#{brand.code}", standard_price: product.standard_price(brand),
      **ProductBrand::DETAILS.to_h { |f| [f, details&.[](f)] }
    })
  end

  # the row's changes applied (not saved yet) and validated: { product, details, changes }
  def stage(product, row, details, errors)
    messages = []
    product_data = (row[:product] || {}).to_h.stringify_keys.slice(*PRODUCT_FIELDS)
    product_data['base_price'] = whole(product_data['base_price'], 'Base price', messages) if product_data.key?('base_price')
    %w[new_arrival active].each { |f| product_data[f] = [true, 'true'].include?(product_data[f]) if product_data.key?(f) }
    %w[image description].each { |f| product_data[f] = product_data[f].to_s.strip.presence if product_data.key?(f) }
    product.set_fields(product_data, product_data.keys)
    messages.concat(readable(product.errors)) unless product.valid?
    changes = Audit.changes_of(product)

    brand_data = (row[:brand] || {}).to_h.stringify_keys.slice(*BRAND_FIELDS)
    if brand_data.any?
      details ||= ProductBrand.new(product_id: product.id, brand_id: brand.id)
      # blank = back to the standard (base price × factor, the product's own photo and description)
      brand_data = brand_data.transform_values { |v| v.to_s.strip.presence }
      brand_data['price'] = whole(brand_data['price'], 'Price', messages) if brand_data.key?('price')
      brand_data['stock_qty'] = whole(brand_data['stock_qty'], 'Stock qty', messages, min: 0) if brand_data.key?('stock_qty')
      details.set_fields(brand_data, brand_data.keys)
      details.updated_by = App.cu.id
      details.updated_at = Time.now
      messages.concat(readable(details.errors)) unless details.valid?
      brand_changes = details.column_changes.slice(*ProductBrand::DETAILS).reject { |_, (from, to)| from == to }
      changes = changes.merge(brand_changes.to_h { |f, pair| ["#{brand.name} #{BRAND_LABELS[f.to_s]}", pair] })
    end

    return errors[product.id] = messages.uniq if messages.any?

    { product: product, details: (details if brand_data.any?), changes: changes }
  end

  # "base_price is not present" → "Base price is not present"
  def readable(errors)
    errors.full_messages.map { |m| m.sub(/\A\w+/) { |f| f.tr('_', ' ').capitalize } }
  end

  def whole(value, label, messages, min: 1)
    return nil if value.nil? || value.to_s.strip.empty?

    n = Integer(value.to_s.strip, exception: false)
    messages << "#{label} must be a whole number#{' of 1 or more' if min == 1}" unless n && n >= min
    n
  end
end
