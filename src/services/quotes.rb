class App::Services::Quotes < App::Services::Base
  def model; Quote; end

  GST_RATE = 0.18
  MAX_ITEMS = 300
  MAX_QUANTITY = 100_000
  NAME_RE = /\A[A-Za-z][A-Za-z .'-]{1,79}\z/
  MOBILE_RE = /\A[6-9]\d{9}\z/

  def self.fields
    {
      save: [:status, :notes]
    }
  end

  # Public: the website saves each quote request a customer sends.
  # Only the customer's choices are accepted — prices, totals and the quote number are worked out here,
  # so nothing the browser sends about money is trusted.
  def submit
    check_presence!(:customer_name, :customer_phone, :items)
    name = params[:customer_name].to_s.strip
    city = params[:customer_city].to_s.strip
    phone = normalize_phone(params[:customer_phone])

    errors = {}
    errors[:customer_name] = 'Invalid name' unless name.match?(NAME_RE)
    errors[:customer_phone] = 'Invalid mobile number' unless phone.match?(MOBILE_RE)
    errors[:customer_city] = 'Invalid city' if city.present? && !city.match?(NAME_RE)
    return_errors!(errors) if errors.present?

    lines = price_lines(params[:items])
    subtotal = lines.sum { |l| l[:amount] || 0 }
    gst = (subtotal * GST_RATE).round

    obj = model.new(
      quote_number: "AT-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(3).upcase}",
      customer_name: name, customer_phone: phone, customer_city: city,
      sent_via: %w[whatsapp email].include?(params[:sent_via]) ? params[:sent_via] : nil,
      items: lines, subtotal: subtotal, gst: gst, total: subtotal + gst
    )
    obj.created_ip = App.cu.ip
    save(obj) { |q| return_success(quote_number: q.quote_number) }
  end

  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.ilike(:customer_name, term) | Sequel.ilike(:customer_phone, term))
    end
    count = ds.count
    return_success(ds.offset(offset).limit(limit).all.map(&:to_pos), total_pages: (count / page_size.to_f).ceil)
  end

  private

  # Same rule as the website: unit price = base price × brand factor, rounded.
  # A line whose brand doesn't make the product is kept unpriced so the shop can suggest an alternative.
  def price_lines(items)
    return_errors!(items: 'Invalid items') unless items.is_a?(Array) && items.size.between?(1, MAX_ITEMS)

    products = Product.where(id: items.map { |i| i[:product_id].to_s }, active: true).to_hash(:id)
    brands = Brand.where(id: items.map { |i| i[:brand_id].to_s }, active: true).to_hash(:id)

    items.map do |i|
      product = products[i[:product_id].to_s] || return_errors!(items: "Unknown product: #{i[:product_id]}")
      quantity = Integer(i[:quantity].to_s, exception: false)
      return_errors!(items: "Invalid quantity for #{product.name}") unless quantity&.between?(1, MAX_QUANTITY)

      brand = brands[i[:brand_id].to_s]
      available = brand.present? && product.brand_ids.to_a.include?(brand.id)
      unit_price = available ? (product.base_price * brand.price_factor.to_f).round : nil
      {
        product_id: product.id, product_name: product.name, category: product.category, unit: product.unit,
        brand_id: brand&.id, brand_name: brand&.name, quantity: quantity,
        unit_price: unit_price, amount: unit_price && unit_price * quantity
      }
    end
  end

  def normalize_phone(phone)
    d = phone.to_s.gsub(/\D/, '')
    return d[2..] if d.length == 12 && d.start_with?('91')
    return d[1..] if d.length == 11 && d.start_with?('0')
    d
  end
end
