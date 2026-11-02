class App::Services::Quotes < App::Services::Base
  def model; Quote; end

  GST_RATE = 0.18
  MAX_ITEMS = 300
  MAX_QUANTITY = 100_000
  NAME_RE = /\A[A-Za-z][A-Za-z .'-]{1,79}\z/
  MOBILE_RE = /\A[6-9]\d{9}\z/
  EMAIL_RE = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  # fields staff can change on a quotation without making a new version
  def self.fields
    {
      save: [:status, :contacted, :notes, :follow_up_on, :valid_until, :assigned_to,
             :customer_name, :customer_phone, :customer_email, :customer_city, :customer_type, :company_name, :gstin]
    }
  end

  # ---- public (website) ----

  # The website saves each quote request a customer sends. Only the customer's choices are accepted —
  # prices, totals and the quotation ID are worked out here, so nothing the browser sends about money is trusted.
  def submit
    check_presence!(:customer_name, :customer_phone, :items)
    customer = customer_details(params)
    lines = price_lines(params[:items], allow_override: false)
    quote = model.new(
      quote_number: Quote.generate_number, source: 'online', status: 'sent',
      sent_via: %w[whatsapp email].include?(params[:sent_via]) ? params[:sent_via] : nil,
      **customer, **pricing(lines)
    )
    quote.created_ip = App.cu.ip
    save(quote) do |q|
      log(q, 'created', "Sent from the website#{" by #{q.sent_via}" if q.sent_via}")
      Audit.log(:quote, q.id, :created, ref: q.base_number, note: "Website request #{q.quote_number} — #{QuotePdf.inr(q.total)}")
      return_success(quote_number: q.quote_number, valid_until: q.valid_until)
    end
  end

  # Anyone with a quotation ID can see that quotation (the ID is not guessable); phone search is staff-only.
  def track
    quote = Quote.find_by_number(qs[:number]) || return_errors!('No quotation found with that ID', 404)
    return_success(quote.public_view)
  end

  # Branded PDF of one quotation (anyone with its ID — same as track)
  def pdf
    quote = Quote.find_by_number(qs[:number]) || return_errors!('No quotation found with that ID', 404)
    send_pdf(QuotePdf.quote(quote), "#{quote.quote_number}.pdf")
  end

  # Side-by-side pros / cons of 2–3 quotations (JSON for the screen)
  def compare
    results = QuoteComparison.compare(comparable_quotes)
    return_success(results.map do |r|
      { quote_number: r[:quote].quote_number, version: r[:quote].version, total: r[:total], savings: r[:savings], badges: r[:badges],
        item_count: r[:quote].items.to_a.size,
        criteria: r[:criteria].map { |c| c.merge(tone: c[:tone]&.to_s) } }
    end)
  end

  # …and as a branded PDF
  def compare_pdf
    quotes = comparable_quotes
    send_pdf(QuotePdf.comparison(quotes, QuoteComparison.compare(quotes)), "Comparison-#{quotes.first.base_number}.pdf")
  end

  # ---- staff (admin) ----

  # newest version of each quotation by default (versions=all lists every version); Limited sales see only their own
  def list
    ds = filtered(Quote.visible_to(staff, qs[:versions] == 'all' ? model.dataset : Quote.latest))
    count = ds.count
    rows = ds.order(Sequel.desc(:created_at)).offset(offset).limit(limit).all
    names = staff_names(rows.map(&:assigned_to))
    version_counts = model.where(base_number: rows.map(&:base_number)).group_and_count(:base_number).to_hash(:base_number, :count)
    return_success(rows.map { |q| q.to_pos.merge('assigned_name' => names[q.assigned_to], 'version_count' => version_counts[q.base_number]) },
                   total_pages: (count / page_size.to_f).ceil, total: count, counts: counts)
  end

  def get
    activities = QuoteActivity.where(base_number: item.base_number).order(Sequel.desc(:created_at)).all
    names = staff_names([item.assigned_to, *activities.map(&:user_id)])
    return_success(item.to_pos.merge(
      'versions' => item.versions.map(&:to_pos), 'assigned_name' => names[item.assigned_to],
      'activities' => activities.map { |a| a.to_pos.merge('user_name' => names[a.user_id]) },
      'can_edit_prices' => staff.can_edit_prices?,
      'order' => Order[base_number: item.base_number]&.values&.slice(:id, :order_number, :status),
      'audit' => AuditLog.where(entity_type: 'quote', ref: item.base_number).order(Sequel.desc(:id)).all.map(&:to_pos),
      # this customer's other quotations (latest versions) — they can be compared when the products match
      'related' => Quote.visible_to(staff, Quote.latest).where(customer_phone: item.customer_phone).exclude(base_number: item.base_number)
                        .order(Sequel.desc(:created_at)).limit(10).all.map { |q| q.values.slice(:id, :quote_number, :total, :status, :created_at) }
    ))
  end

  # The customer accepted: mark the quotation accepted and copy it into an order (one order per quotation)
  def convert
    quote = item
    existing = Order[base_number: quote.base_number]
    return_errors!("This quotation is already order #{existing.order_number}") if existing
    return_errors!('Every item needs a brand and a price before it can become an order') if quote.items.to_a.any? { |i| i['amount'].nil? }
    App.db.transaction do
      order = Order.from_quote(quote, App.cu.id)
      return_errors!(order.errors) unless order.save
      quote.update(status: 'accepted', contacted: true, contacted_at: quote.contacted_at || Time.now)
      log(quote, 'status', "Accepted — order #{order.order_number}")
      Audit.log(:quote, quote.id, :accepted, ref: quote.base_number, note: "Converted to order #{order.order_number}")
      Audit.log(:order, order.id, :created, ref: order.order_number, note: "From quotation #{quote.quote_number} — #{QuotePdf.inr(order.total)}")
      return_success(order.to_pos)
    end
  end

  def update
    data = data_for(:save)
    data.delete('assigned_to') if staff.limited? # only Admin / Sales reassign quotations
    status_was = item.status
    if data.key?('contacted')
      contacted = [true, 'true'].include?(data['contacted'])
      data['contacted'] = contacted
      data['contacted_at'] = contacted ? (item.contacted_at || Time.now) : nil
    end
    data['customer_phone'] = normalize_phone(data['customer_phone']) if data.key?('customer_phone')
    item.set_fields(data, data.keys)
    item.valid? # applies the status ↔ contacted rules before the changes are recorded
    changes = Audit.changes_of(item)
    save(item) do |q|
      log(q, 'status', "Status changed to #{q.status}") if q.status != status_was
      Audit.log(:quote, q.id, :updated, ref: q.base_number, changes: changes, note: q.quote_number) if changes.any?
      return_success(q.to_pos)
    end
  end

  # Follow-up actions: a call, WhatsApp, visit, email or note, with the next follow-up date. Reaching the customer
  # marks the quotation contacted; the next date (or none) becomes its follow-up date.
  def log_activity
    check_presence!(:kind)
    kind = params[:kind].to_s
    return_errors!(kind: 'Choose call, WhatsApp, visit, email or note') unless %w[call whatsapp visit email note].include?(kind)
    next_on = date?(params[:next_follow_up_on]) ? Date.parse(params[:next_follow_up_on]) : nil
    App.db.transaction do
      activity = log(item, kind, params[:note].to_s.strip.presence, next_on)
      changes = { follow_up_on: next_on }
      changes.merge!(contacted: true, contacted_at: item.contacted_at || Time.now) if QuoteActivity::CONTACT_KINDS.include?(kind)
      item.set(changes)
      audit = Audit.changes_of(item)
      item.save
      Audit.log(:quote, item.id, :follow_up, ref: item.base_number, changes: audit, note: [kind, params[:note].to_s.strip.presence].compact.join(': '))
      return_success(activity.to_pos)
    end
  end

  # A quotation created by the sales team — walk-in, phone or WhatsApp customers
  def create
    check_presence!(:customer_name, :customer_phone, :items)
    customer = customer_details(params, staff: true)
    lines = price_lines(params[:items], allow_override: staff.can_edit_prices?)
    quote = model.new(
      quote_number: Quote.generate_number,
      source: Quote::SOURCES.include?(params[:source]) ? params[:source] : 'walk_in',
      notes: params[:notes], assigned_to: (staff.limited? ? nil : params[:assigned_to].presence) || App.cu.id,
      follow_up_on: (Date.parse(params[:follow_up_on]) if date?(params[:follow_up_on])),
      valid_until: (Date.parse(params[:valid_until]) if date?(params[:valid_until])),
      created_by: App.cu.id, **customer, **pricing(lines)
    )
    quote.created_ip = App.cu.ip
    save(quote) do |q|
      log(q, 'created', "Created (#{q.source.tr('_', '-')})")
      Audit.log(:quote, q.id, :created, ref: q.base_number, note: "#{q.quote_number} (#{q.source.tr('_', '-')}) — #{QuotePdf.inr(q.total)}")
      return_success(q.to_pos)
    end
  end

  # Changing brands, quantities or prices makes a new version (AT-…-001, -002 …); the earlier one stays as it was sent.
  def revise
    check_presence!(:items)
    parent = item
    lines = price_lines(params[:items], allow_override: staff.can_edit_prices?)
    next_version = model.where(base_number: parent.base_number).max(:version).to_i + 1
    # the conversation with the customer carries on: contacted / follow-up come over to the new version
    copy = parent.values.slice(:customer_name, :customer_phone, :customer_email, :customer_city, :customer_type,
                               :company_name, :gstin, :source, :assigned_to, :follow_up_on, :contacted, :contacted_at)
    # …and so does its status: a draft stays a draft, a quotation already shared stays shared (reopened if it was closed)
    copy[:status] = Quote::IN_PROGRESS.include?(parent.status) ? parent.status : 'sent'
    quote = model.new(
      **copy, quote_number: Quote.number_for(parent.base_number, next_version), base_number: parent.base_number,
      version: next_version, parent_id: parent.id, notes: params[:notes].presence || parent.notes,
      created_by: App.cu.id, **pricing(lines)
    )
    save(quote) do |q|
      log(q, 'version', "New version #{q.quote_number} — #{QuotePdf.inr(q.total)}")
      Audit.log(:quote, q.id, :new_version, ref: q.base_number, note: "#{parent.quote_number} → #{q.quote_number}",
                changes: { lines: Audit.line_changes(parent.items, q.items), total: [parent.total, q.total] })
      return_success(q.to_pos)
    end
  end

  private

  def staff
    App.cu.user_obj
  end

  # one quotation the signed-in staff member may see (others don't exist for them)
  def item(id = rp[:id])
    @item ||= Quote.visible_to(staff).where(id: id.to_i).first || return_errors!('No quotation found', 404)
  end

  def log(quote, kind, note = nil, next_on = nil)
    QuoteActivity.create(base_number: quote.base_number, quote_id: quote.id, kind: kind, note: note, next_follow_up_on: next_on, user_id: App.cu.id)
  end

  def send_pdf(data, filename)
    request.response['Content-Type'] = 'application/pdf'
    request.response['Content-Disposition'] = %(inline; filename="#{filename}")
    data
  end

  # ?numbers=A,B,C — 2 or 3 quotations of one customer, with the same products and quantities (only brands / prices differ)
  def comparable_quotes
    numbers = qs[:numbers].to_s.split(',').map { |n| n.strip.upcase }.reject(&:empty?).uniq
    return_errors!("Choose 2 or #{QuoteComparison::MAX} quotations to compare") unless numbers.size.between?(2, QuoteComparison::MAX)
    quotes = numbers.map { |n| Quote.find_by_number(n) || return_errors!("No quotation found with ID #{n}", 404) }
    return_errors!('Only quotations for the same customer can be compared') unless quotes.map(&:customer_phone).uniq.size == 1
    return_errors!('These quotations have different products or quantities — only the brands may differ to compare them') unless QuoteComparison.same_products?(quotes)
    quotes
  end

  # filters from the quotations list (all optional): search, status, contacted, validity, follow_up, source,
  # customer_type, from, to (dates), assigned_to
  def filtered(ds)
    today = Date.today
    if qs[:search].present?
      term = qs[:search].strip
      digits = term.gsub(/\D/, '')
      cond = Sequel.ilike(:quote_number, "%#{term}%") | Sequel.ilike(:customer_name, "%#{term}%") | Sequel.ilike(:company_name, "%#{term}%")
      cond |= Sequel.like(:customer_phone, "%#{digits.last(10)}%") if digits.length >= 4
      ds = ds.where(cond)
    end
    ds = ds.where(status: qs[:status]) if Quote::STATUSES.include?(qs[:status])
    ds = ds.where(status: Quote::IN_PROGRESS) if qs[:status] == 'in_progress'
    ds = ds.where(contacted: qs[:contacted] == 'true') if %w[true false].include?(qs[:contacted])
    ds = ds.where(source: qs[:source]) if Quote::SOURCES.include?(qs[:source])
    ds = ds.where(customer_type: qs[:customer_type]) if Quote::CUSTOMER_TYPES.include?(qs[:customer_type])
    ds = ds.where(assigned_to: qs[:assigned_to].to_i) if qs[:assigned_to].present?
    # (worked out first: Sequel runs these blocks where the service's own methods aren't available)
    from = date?(qs[:from]) && Date.parse(qs[:from])
    to = date?(qs[:to]) && Date.parse(qs[:to]) + 1
    ds = ds.where { created_at >= from } if from
    ds = ds.where { created_at < to } if to
    case qs[:validity]
    when 'valid' then ds = ds.where { valid_until >= today }
    when 'expiring' then ds = ds.where(status: Quote::IN_PROGRESS).where { (valid_until >= today) & (valid_until <= today + 3) }
    when 'expired' then ds = ds.where(status: Quote::IN_PROGRESS).where { valid_until < today }
    end
    case qs[:follow_up]
    when 'due' then ds = ds.where(status: Quote::IN_PROGRESS).where { follow_up_on <= today } # today's and overdue
    when 'overdue' then ds = ds.where(status: Quote::IN_PROGRESS).where { follow_up_on < today }
    when 'upcoming' then ds = ds.where { follow_up_on > today }
    end
    ds
  end

  # numbers for the filter tabs
  def counts
    today = Date.today
    all = Quote.visible_to(staff, Quote.latest)
    {
      all: all.count,
      draft: all.where(status: 'draft').count,
      contacted: all.where(status: 'contacted').count,
      accepted: all.where(status: 'accepted').count,
      lost: all.where(status: 'lost').count,
      expired: all.where(status: Quote::IN_PROGRESS).where { valid_until < today }.count,
      not_contacted: all.where(contacted: false, status: Quote::IN_PROGRESS).count,
      follow_up_due: all.where(status: Quote::IN_PROGRESS).where { follow_up_on <= today }.count,
      expiring: all.where(status: Quote::IN_PROGRESS).where { (valid_until >= today) & (valid_until <= today + 3) }.count
    }
  end

  def date?(value)
    value.present? && Date.parse(value.to_s)
  rescue Date::Error
    false
  end

  def staff_names(ids)
    ids = ids.compact.uniq
    ids.empty? ? {} : User.where(id: ids).to_hash(:id, :full_name)
  end

  # Name, mobile (Indian, 10 digits), optional email / city, and B2B details
  def customer_details(data, staff: false)
    name = data[:customer_name].to_s.strip
    city = data[:customer_city].to_s.strip
    phone = normalize_phone(data[:customer_phone])
    email = data[:customer_email].to_s.strip.downcase.presence
    type = data[:customer_type] == 'B2B' || data[:company_name].present? ? 'B2B' : 'B2C'

    errors = {}
    errors[:customer_name] = 'Invalid name' unless staff ? name.length.between?(2, 80) : name.match?(NAME_RE)
    errors[:customer_phone] = 'Invalid mobile number' unless phone.match?(MOBILE_RE)
    errors[:customer_city] = 'Invalid city' if city.present? && !city.match?(NAME_RE)
    errors[:customer_email] = 'Invalid email' if email && !email.match?(EMAIL_RE)
    return_errors!(errors) if errors.present?

    { customer_name: name, customer_phone: phone, customer_city: city.presence, customer_email: email, customer_type: type,
      company_name: data[:company_name].to_s.strip.presence, gstin: data[:gstin].to_s.strip.upcase.presence }
  end

  def pricing(lines)
    subtotal = lines.sum { |l| l[:amount] || 0 }
    gst = (subtotal * GST_RATE).round
    { items: lines, subtotal: subtotal, gst: gst, total: subtotal + gst }
  end

  # List price = the brand's own price for the product if set, else base price × brand factor, rounded (same rule as the website). Staff may set their own unit price
  # (allow_override); the list price is kept next to it. A line whose brand doesn't make the product stays unpriced
  # so the shop can suggest an alternative.
  def price_lines(items, allow_override:)
    return_errors!(items: 'Invalid items') unless items.is_a?(Array) && items.size.between?(1, MAX_ITEMS)

    products = Product.where(id: items.map { |i| i[:product_id].to_s }).to_hash(:id)
    alternative_ids = allow_override ? items.flat_map { |i| Array(i[:alternative_brand_ids]).map(&:to_s) } : []
    brands = Brand.where(id: items.map { |i| i[:brand_id].to_s } + alternative_ids).to_hash(:id)
    details = ProductBrand.where(product_id: products.keys).to_hash([:product_id, :brand_id])

    items.map do |i|
      product = products[i[:product_id].to_s]
      return_errors!(items: "Unknown product: #{i[:product_id]}") unless product && (product.active || allow_override)
      quantity = Integer(i[:quantity].to_s, exception: false)
      return_errors!(items: "Invalid quantity for #{product.name}") unless quantity&.between?(1, MAX_QUANTITY)

      brand = brands[i[:brand_id].to_s]
      available = brand.present? && product.brand_ids.to_a.include?(brand.id)
      list_price = available ? product.price_for(brand, details[[product.id, brand.id]]) : nil
      return_errors!(items: 'Only Sales or Admin can change prices') if !allow_override && i[:unit_price].present? && App.cu.id
      override = allow_override && available && i[:unit_price].present? ? Integer(i[:unit_price].to_s, exception: false) : nil
      return_errors!(items: "Invalid price for #{product.name}") if allow_override && i[:unit_price].present? && !override&.positive?
      unit_price = override || list_price
      specs = brand&.specs.to_h || {}
      # other brands the customer could choose instead (staff pick them), each at its list price
      alternatives = (allow_override ? Array(i[:alternative_brand_ids]).map(&:to_s).uniq : []).filter_map do |alt_id|
        alt = brands[alt_id]
        next if alt.nil? || alt.id == brand&.id || !product.brand_ids.to_a.include?(alt.id)
        { brand_id: alt.id, brand_name: alt.name, dynamic_code: "#{product.code}-#{alt.code}", unit_price: product.price_for(alt, details[[product.id, alt.id]]), warranty: alt.specs.to_h['warranty'] }.compact
      end
      {
        product_id: product.id, product_code: product.code, product_name: product.name, category: product.category, unit: product.unit,
        brand_id: brand&.id, brand_name: brand&.name, brand_code: brand&.code,
        dynamic_code: brand && product.code && "#{product.code}-#{brand.code}", quantity: quantity,
        list_price: list_price, unit_price: unit_price, overridden: override.present? && override != list_price,
        amount: unit_price && unit_price * quantity, note: i[:note].to_s.strip.presence,
        stock_status: (details[[product.id, brand.id]]&.stock_status if available),
        warranty: specs['warranty'], guarantee: specs['guarantee'], benefits: (i[:benefits].to_s.strip.presence if allow_override),
        alternatives: alternatives.presence
      }.compact
    end
  end

  def normalize_phone(phone)
    d = phone.to_s.gsub(/\D/, '')
    return d[2..] if d.length == 12 && d.start_with?('91')
    return d[1..] if d.length == 11 && d.start_with?('0')
    d
  end
end
