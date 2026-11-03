require 'roo'
require 'tempfile'

# Reads the client's filled-in product template (Product_Details_Template.xlsx: Products, Brand prices & stock, Brands)
# and works out — without saving anything — what it would add and change, with every problem by sheet and row.
# `apply!` then writes it all in one transaction (all or nothing), with an audit entry for every change.
#
# Matching: a product by its item code / SKU if given, else by name (case doesn't matter); a brand or category by
# name. Blank optional cells leave an existing product's value as it is. A product with rows in "Brand prices &
# stock" gets exactly those brands, at those prices.
class ProductImport
  Error = Class.new(StandardError)

  SHEETS = { products: 'Products', prices: 'Brand prices & stock', brands: 'Brands' }.freeze
  REQUIRED = {
    products: ['Product name', 'Category', 'Unit', 'Base price', 'GST rate'],
    prices: ['Product name', 'Brand', 'Price for this brand'],
    brands: ['Brand name']
  }.freeze
  HEADER_SEARCH_ROWS = 10 # the header row is found by its first column's name, in the first rows of each sheet
  EXAMPLES = ['door hinges 4 inch ss', 'bwp plywood 18 mm'].freeze # the template's grey example rows
  STOCK = { 'in stock' => 'in_stock', 'few left' => 'low_stock', 'out of stock' => 'out_of_stock', 'on order' => 'on_order' }.freeze
  TIERS = %w[Premium Standard Economy].freeze
  GST_RATES = [0, 5, 12, 18, 28].freeze
  SPECS = { 'warranty' => 'Warranty', 'guarantee' => 'Guarantee', 'material' => 'Material', 'finish' => 'Finish options',
            'certification' => 'Certification', 'origin' => 'Brand origin', 'support' => 'After-sales support' }.freeze
  # what an audit entry calls each product column
  LABELS = { name: 'Name', category: 'Category', unit: 'Unit', base_price: 'Base price', gst_rate: 'GST rate', hsn_code: 'HSN code',
             specification: 'Specification', description: 'Description', image: 'Photo', active: 'Shown on website',
             new_arrival: 'New arrival', sku: 'Item code / SKU', brand_ids: 'Brands' }.freeze
  MAX_ERRORS = 300

  attr_reader :errors, :warnings

  def initialize(bytes, hide_missing: false)
    @hide_missing = hide_missing
    @errors = []
    @warnings = []
    @file = Tempfile.new(['products', '.xlsx'])
    @file.binmode
    @file.write(without_empty_results(bytes))
    @file.flush
    @book = Roo::Excelx.new(@file.path)
  rescue Zip::Error, ArgumentError, IOError, Nokogiri::XML::SyntaxError
    raise Error, 'This is not an Excel (.xlsx) file — please send the filled-in template'
  end

  # What the import would do: { ok, errors, warnings, summary, samples }
  def preview
    plan
    {
      ok: @errors.empty?, errors: @errors.first(MAX_ERRORS), error_count: @errors.size, warnings: @warnings,
      summary: {
        products_new: @new_products.size, products_updated: @updated_products.size,
        products_unchanged: @unchanged_count, products_hidden: @hidden.size, brand_prices: @price_rows.size,
        brands_new: @new_brands.map { |b| b[:name] }, brands_updated: @updated_brands.size,
        categories_new: @new_categories, series_new: @new_series.size
      },
      samples: {
        new: @new_products.first(15).map { |p| p[:name] },
        updated: @updated_products.first(15).map { |u| { name: u[:name], changes: describe(u[:changes]) } },
        hidden: @hidden.first(15).map { |p| p[:name] }
      }
    }
  end

  # Writes the plan (call after `preview` came back ok). Returns the summary and the audit batch.
  def apply!(batch_id:)
    raise Error, 'The file has problems — check it first' unless plan && @errors.empty?

    user_id = App.cu.id
    now = Time.now
    audit = []
    db = App::Models::Product.db
    db.transaction do
      @new_categories.each_with_index do |name, i|
        db[:categories].insert(name: name, icon: 'box', position: 100 + i, active: true, created_by: user_id)
        audit << { entity_type: :category, entity_id: name, ref: name, action: :created, note: 'Imported' }
      end

      @new_brands.each do |b|
        db[:brands].insert(id: b[:id], name: b[:name], code: b[:code], tier: b[:tier], price_factor: 1, specs: Sequel.pg_jsonb(b[:specs]),
                           active: b[:active], position: 100, created_by: user_id)
        audit << { entity_type: :brand, entity_id: b[:id], ref: b[:code], action: :created, note: "#{b[:name]} · imported" }
      end
      @updated_brands.each do |b|
        db[:brands].where(id: b[:id]).update(b[:values].merge(updated_by: user_id, updated_at: now))
        audit << { entity_type: :brand, entity_id: b[:id], ref: b[:code], action: :updated, changes: b[:changes], note: "#{b[:name]} · imported" }
      end

      series_ids = create_series(db, user_id)

      new_rows = @new_products.map do |p|
        p[:values].merge(id: p[:id], code: p[:code], brand_ids: Sequel.pg_array(p[:brand_ids], :text),
                         series_ids: Sequel.pg_array(p[:series_keys].map { |k| series_ids[k] }.compact, :integer), created_by: user_id)
      end
      db[:products].multi_insert(new_rows, slice: 300) if new_rows.any?
      @new_products.each do |p|
        audit << { entity_type: :product, entity_id: p[:id], ref: p[:code], action: :created, note: "#{p[:name]} · imported",
                   changes: p[:brand_changes] }
      end

      @updated_products.each do |u|
        values = u[:values].dup
        values[:brand_ids] = Sequel.pg_array(values[:brand_ids], :text) if values.key?(:brand_ids)
        values[:series_ids] = Sequel.pg_array(u[:series_keys].map { |k| series_ids[k] }.compact, :integer) if u[:series_keys]
        db[:products].where(id: u[:id]).update(values.merge(updated_by: user_id, updated_at: now)) if values.any?
        audit << { entity_type: :product, entity_id: u[:id], ref: u[:code], action: :imported, changes: u[:changes], note: "#{u[:name]} · imported" }
      end

      # each listed product's brand prices / stock: replaced by what the file says
      db[:product_brands].where(product_id: @priced_product_ids).delete if @priced_product_ids.any?
      details = @price_rows.map { |d| d.slice(:product_id, :brand_id, :price, :stock_status, :stock_qty, :image, :description).merge(updated_by: user_id, updated_at: now) }
      db[:product_brands].multi_insert(details, slice: 500) if details.any?

      if @hidden.any?
        db[:products].where(id: @hidden.map { |p| p[:id] }).update(active: false, updated_by: user_id, updated_at: now)
        @hidden.each { |p| audit << { entity_type: :product, entity_id: p[:id], ref: p[:code], action: :hidden, note: "#{p[:name]} · not in the imported file" } }
      end

      Audit.log_many(audit, batch_id: batch_id)
    end
    { summary: preview[:summary], batch_id: batch_id }
  ensure
    @file&.close!
  end

  private

  # ---- reading the sheets ----

  def plan
    return true if @planned

    @planned = true
    @new_products, @updated_products, @price_rows, @priced_product_ids, @hidden = [], [], [], [], []
    @new_brands, @updated_brands, @new_categories, @new_series = [], [], [], []
    @unchanged_count = 0
    load_database
    brands = read_brands
    products = read_products
    prices = read_prices(products, brands)
    if @examples&.any?
      note("Skipped the grey example rows (#{@examples.map { |sheet, rows| "#{SHEETS[sheet]} row#{'s' if rows.size > 1} #{rows.join(', ')}" }.join('; ')})")
    end
    resolve(products, brands, prices) if @errors.empty?
    true
  end

  def sheet_rows(key)
    name = SHEETS[key]
    raise Error, "The sheet “#{name}” is missing — please use our template" unless @book.sheets.include?(name)

    sheet = @book.sheet(name)
    clean = ->(row) { row.map { |h| h.to_s.sub(/\s*\*\s*\z/, '').strip } }
    last = sheet.last_row.to_i
    header_row = (1..[HEADER_SEARCH_ROWS, last].min).find { |r| clean.(sheet.row(r)).any? { |h| h.downcase.start_with?(REQUIRED[key].first.downcase) } }
    raise Error, "Couldn't find the column headings in the “#{name}” sheet — please use our template" unless header_row

    headers = clean.(sheet.row(header_row))
    missing = REQUIRED[key].reject { |want| headers.any? { |h| h.downcase.start_with?(want.downcase) } }
    raise Error, "The “#{name}” sheet is missing the column(s): #{missing.join(', ')} — please use our template" if missing.any?
    return [] unless last > header_row

    (header_row + 1..last).filter_map do |r|
      cells = headers.zip(sheet.row(r)).reject { |h, _| h.empty? || h.start_with?('Product found') }.to_h
      next if cells.values.all? { |v| text(v).empty? }

      [r, cells]
    end
  end

  def read_brands
    sheet_rows(:brands).filter_map do |row, cells|
      name = text(field(cells, 'Brand name'))
      next problem(:brands, row, 'Brand name is missing') if name.empty?

      tier = text(field(cells, 'Tier')).capitalize.presence
      next problem(:brands, row, "Tier must be #{TIERS.join(', ')}") if tier && !TIERS.include?(tier)

      active = yes_no(field(cells, 'Keep on website'))
      next problem(:brands, row, 'Keep on website must be Yes or No') if active == :invalid

      { row: row, name: name, key: name.downcase, tier: tier, active: active.nil? ? true : active,
        specs: SPECS.to_h { |key, head| [key, text(field(cells, head)).presence] }.compact }
    end.to_h { |b| [b[:key], b] }
  end

  def read_products
    seen = {}
    sheet_rows(:products).filter_map do |row, cells|
      name = text(field(cells, 'Product name'))
      next skipped_example(:products, row) if EXAMPLES.include?(name.downcase)

      issues = []
      issues << 'Product name is missing' if name.empty?
      issues << 'Product name is too long (120 letters at most)' if name.length > 120
      key = name.downcase
      issues << "“#{name}” is listed twice (also row #{seen[key]})" if seen[key] && !name.empty?
      seen[key] ||= row
      category = text(field(cells, 'Category'))
      issues << 'Category is missing' if category.empty?
      unit = text(field(cells, 'Unit')).downcase
      issues << 'Unit is missing' if unit.empty?
      price = whole(field(cells, 'Base price'))
      issues << 'Base price must be a whole number of 1 or more (₹, before GST)' unless price&.positive?
      gst = gst_rate(field(cells, 'GST rate'))
      issues << 'GST rate must be 0, 5, 12, 18 or 28%' unless gst
      show = yes_no(field(cells, 'Show on website'))
      issues << 'Show on website must be Yes or No' if show == :invalid
      fresh = yes_no(field(cells, 'New arrival'))
      issues << 'New arrival must be Yes or No' if fresh == :invalid
      next problem(:products, row, issues) if issues.any?

      photo = text(field(cells, 'Photo'))
      {
        row: row, name: name, key: key, sku: text(field(cells, 'Your item code')).presence, category: category, unit: unit,
        base_price: price, gst_rate: gst, hsn_code: text(field(cells, 'HSN')).presence,
        specification: text(field(cells, 'Size')).presence, description: text(field(cells, 'Description')).presence,
        image: (photo if link?(photo)), photo_file: (photo.presence unless link?(photo)), active: show, new_arrival: fresh
      }
    end.to_h { |p| [p[:key], p] }
  end

  def read_prices(products, brands)
    seen = {}
    sheet_rows(:prices).filter_map do |row, cells|
      product_name = text(field(cells, 'Product name'))
      next skipped_example(:prices, row) if EXAMPLES.include?(product_name.downcase)

      brand_name = text(field(cells, 'Brand'))
      issues = []
      product_key = product_name.downcase
      brand_key = brand_name.downcase
      issues << 'Product name is missing' if product_name.empty?
      issues << 'Brand is missing' if brand_name.empty?
      if !product_name.empty? && !products.key?(product_key) && !@db_products_by_name.key?(product_key)
        issues << "“#{product_name}” is not in the Products sheet (names must match exactly)"
      end
      if !brand_name.empty? && !brands.key?(brand_key) && !@db_brands_by_name.key?(brand_key)
        issues << "Brand “#{brand_name}” is not in the Brands sheet"
      end
      pair = [product_key, brand_key]
      issues << "#{product_name} in #{brand_name} is listed twice (also row #{seen[pair]})" if seen[pair] && issues.empty?
      seen[pair] ||= row
      price = whole(field(cells, 'Price for this brand'))
      issues << 'Price must be a whole number of 1 or more (₹, before GST)' unless price&.positive?
      stock_text = text(field(cells, 'Stock')).downcase
      stock = stock_text.empty? ? nil : STOCK[stock_text]
      issues << 'Stock must be In stock, Few left, Out of stock or On order' if !stock_text.empty? && stock.nil?
      qty_cell = field(cells, 'Stock quantity')
      qty = text(qty_cell).empty? ? nil : whole(qty_cell)
      issues << 'Stock quantity must be a whole number, 0 or more' if !text(qty_cell).empty? && !(qty && qty >= 0)
      next problem(:prices, row, issues) if issues.any?

      photo = text(field(cells, 'Photo'))
      warranty = text(field(cells, 'Warranty')).presence
      notes = [text(field(cells, 'Notes')).presence, (warranty && "Warranty: #{warranty}")].compact.join(' · ').presence
      { row: row, product_key: product_key, brand_key: brand_key, price: price, stock_status: stock, stock_qty: qty,
        series: text(field(cells, 'Series')).presence, image: (photo if link?(photo)), description: notes }
    end
  end

  # ---- matching against the database and working out the changes ----

  def load_database
    @db_products = App::Models::Product.dataset.all
    @db_products_by_name = @db_products.group_by { |p| p[:name].to_s.downcase }.transform_values(&:first)
    @db_products_by_sku = @db_products.select { |p| p[:sku].present? }.to_h { |p| [p[:sku].downcase, p] }
    @db_brands = App::Models::Brand.dataset.all
    @db_brands_by_name = @db_brands.to_h { |b| [b[:name].downcase, b] }
    @db_categories = App::Models::Category.dataset.select_map(:name).to_h { |n| [n.downcase, n] }
    @db_series = App::Models::BrandSeries.dataset.all.to_h { |s| [[s[:brand_id], s[:name].downcase], s[:id]] }
    @db_details = App::Models::ProductBrand.dataset.all.group_by { |d| d[:product_id] }
    @taken_product_ids = @db_products.map { |p| p[:id] }.to_set
    @taken_brand_ids = @db_brands.map { |b| b[:id] }.to_set
    @taken_brand_codes = @db_brands.map { |b| b[:code] }.compact.to_set
    @next_code = (@db_products.map { |p| p[:code].to_s[/\AAT(\d+)\z/, 1].to_i }.max || 1000).clamp(1000..) + 1
  end

  def resolve(products, brands, prices)
    # brands: update listed ones, create new ones
    @new_brands = []
    @updated_brands = []
    brand_ids = {}
    brands.each_value do |b|
      if (existing = @db_brands_by_name[b[:key]])
        brand_ids[b[:key]] = existing[:id]
        changes = {}
        values = {}
        if b[:tier] && b[:tier] != existing[:tier]
          changes['Tier'] = [existing[:tier], b[:tier]]
          values[:tier] = b[:tier]
        end
        if b[:active] != existing[:active]
          changes['Shown on website'] = [existing[:active], b[:active]]
          values[:active] = b[:active]
        end
        old_specs = existing[:specs].to_h
        new_specs = old_specs.merge(b[:specs])
        if new_specs != old_specs
          b[:specs].each { |k, v| changes[SPECS[k]] = [old_specs[k], v] if old_specs[k] != v }
          values[:specs] = Sequel.pg_jsonb(new_specs)
        end
        @updated_brands << { id: existing[:id], code: existing[:code], name: existing[:name], values: values, changes: changes } if values.any?
      else
        id = unique_slug(b[:name], @taken_brand_ids)
        code = brand_code(b[:name])
        brand_ids[b[:key]] = id
        @new_brands << b.merge(id: id, code: code, tier: b[:tier] || 'Standard')
      end
    end
    @db_brands_by_name.each { |key, b| brand_ids[key] ||= b[:id] }
    brand_names = @db_brands.to_h { |b| [b[:id], b[:name]] }.merge(@new_brands.to_h { |b| [b[:id], b[:name]] })

    # categories named in the file that don't exist yet
    @new_categories = products.values.map { |p| p[:category] }.uniq { |c| c.downcase }.reject { |c| @db_categories.key?(c.downcase) }
    category_names = @db_categories.merge(@new_categories.to_h { |c| [c.downcase, c] })

    # series named in the file that don't exist yet: [brand_id, series name]
    @new_series = prices.filter_map { |d| [brand_ids[d[:brand_key]], d[:series]] if d[:series] }
                        .uniq { |id, name| [id, name.downcase] }.reject { |id, name| @db_series.key?([id, name.downcase]) }

    by_product = prices.group_by { |d| d[:product_key] }
    @new_products = []
    @updated_products = []
    @unchanged_count = 0
    @price_rows = []
    @priced_product_ids = []
    matched = Set.new
    photo_files = 0

    products.each_value do |p|
      existing = (p[:sku] && @db_products_by_sku[p[:sku].downcase]) || @db_products_by_name[p[:key]]
      p[:category] = category_names[p[:category].downcase]
      photo_files += 1 if p[:photo_file]
      rows = by_product[p[:key]] || []
      brand_list = rows.map { |d| brand_ids[d[:brand_key]] }
      series_keys = rows.filter_map { |d| [brand_ids[d[:brand_key]], d[:series].downcase] if d[:series] }

      if existing
        matched << existing[:id]
        values = changed_values(existing, p)
        changes = values.to_h { |k, v| [LABELS[k], [plain(existing[k]), v]] }
        if rows.any?
          @priced_product_ids << existing[:id]
          if brand_list.sort != existing[:brand_ids].to_a.sort
            values[:brand_ids] = brand_list
            changes['Brands'] = [existing[:brand_ids].to_a.map { |id| brand_names[id] || id }.join(', '), brand_list.map { |id| brand_names[id] }.join(', ')]
          end
          changes.merge!(detail_changes(existing[:id], rows, brand_ids, brand_names))
        end
        if changes.any?
          @updated_products << { id: existing[:id], code: existing[:code], name: p[:name], values: values, changes: changes,
                                 series_keys: (series_keys if rows.any?) }
        else
          @unchanged_count += 1
        end
        product_id = existing[:id]
      else
        product_id = unique_slug(p[:name], @taken_product_ids)
        code = "AT#{@next_code}"
        @next_code += 1
        warn_once(:no_brand, "#{p[:name]} has no rows in “Brand prices & stock” — it won't show on the website until it has a brand") if rows.empty?
        @priced_product_ids << product_id if rows.any?
        @new_products << {
          id: product_id, code: code, name: p[:name], brand_ids: brand_list, series_keys: series_keys,
          brand_changes: detail_changes(product_id, rows, brand_ids, brand_names),
          values: { name: p[:name], category: p[:category], unit: p[:unit], base_price: p[:base_price], gst_rate: p[:gst_rate],
                    hsn_code: p[:hsn_code], specification: p[:specification], description: p[:description], image: p[:image],
                    sku: p[:sku], active: p[:active].nil? ? true : p[:active], new_arrival: p[:new_arrival] || false, mock: false }
        }
      end
      rows.each do |d|
        @price_rows << d.slice(:price, :stock_status, :stock_qty, :image, :description).merge(product_id: product_id, brand_id: brand_ids[d[:brand_key]])
      end
    end

    # brand rows for products already on the website that aren't in the Products sheet
    (by_product.keys - products.keys).each do |key|
      existing = @db_products_by_name[key]
      rows = by_product[key]
      matched << existing[:id]
      @priced_product_ids << existing[:id]
      brand_list = rows.map { |d| brand_ids[d[:brand_key]] }
      changes = detail_changes(existing[:id], rows, brand_ids, brand_names)
      values = {}
      if brand_list.sort != existing[:brand_ids].to_a.sort
        values[:brand_ids] = brand_list
        changes['Brands'] = [existing[:brand_ids].to_a.map { |id| brand_names[id] || id }.join(', '), brand_list.map { |id| brand_names[id] }.join(', ')]
      end
      series_keys = rows.filter_map { |d| [brand_ids[d[:brand_key]], d[:series].downcase] if d[:series] }
      @updated_products << { id: existing[:id], code: existing[:code], name: existing[:name], values: values, changes: changes, series_keys: series_keys } if changes.any?
      rows.each { |d| @price_rows << d.slice(:price, :stock_status, :stock_qty, :image, :description).merge(product_id: existing[:id], brand_id: brand_ids[d[:brand_key]]) }
    end

    @hidden = @hide_missing ? @db_products.select { |p| p[:active] && !matched.include?(p[:id]) } : []

    note("#{photo_files} photo(s) are file names — send us the photo files and we'll add them") if photo_files.positive?
    other_gst = products.values.count { |p| p[:gst_rate] != 18 }
    note("#{other_gst} product(s) have a GST rate other than 18% — saved, but quotations still use 18% for every product until per-product GST is switched on") if other_gst.positive?
    note("#{@new_categories.size} new categor#{@new_categories.size == 1 ? 'y' : 'ies'} will be created: #{@new_categories.join(', ')}") if @new_categories.any?
    @warn_counts&.each { |_, (first, count)| note(count > 1 ? "#{first} (and #{count - 1} more like it)" : first) }
  end

  # values on the sheet that differ from the product on the website (blank optional cells change nothing)
  def changed_values(existing, row)
    values = {}
    { name: row[:name], category: row[:category], unit: row[:unit], base_price: row[:base_price], gst_rate: row[:gst_rate] }.each do |k, v|
      values[k] = v if existing[k] != v
    end
    %i[hsn_code specification description image sku active new_arrival].each do |k|
      v = row[k]
      values[k] = v if !v.nil? && existing[k] != v
    end
    values[:mock] = false if existing[:mock]
    values
  end

  # "Godrej price: 122 → 130", "Godrej stock: — → In stock" for one product's brand rows
  def detail_changes(product_id, rows, brand_ids, brand_names)
    before = (@db_details[product_id] || []).to_h { |d| [d[:brand_id], d] }
    rows.each_with_object({}) do |d, changes|
      brand_id = brand_ids[d[:brand_key]]
      old = before[brand_id] || {}
      name = brand_names[brand_id]
      changes["#{name} price"] = [old[:price], d[:price]] if old[:price] != d[:price]
      label = STOCK.invert.transform_values(&:capitalize)
      changes["#{name} stock"] = [label[old[:stock_status]], label[d[:stock_status]]] if old[:stock_status] != d[:stock_status]
      changes["#{name} stock qty"] = [old[:stock_qty], d[:stock_qty]] if old[:stock_qty] != d[:stock_qty]
      changes["#{name} notes"] = [old[:description], d[:description]] if d[:description] && old[:description] != d[:description]
      changes["#{name} photo"] = [old[:image], d[:image]] if d[:image] && old[:image] != d[:image]
    end
  end

  def create_series(db, user_id)
    ids = @db_series.transform_keys { |(brand_id, name)| [brand_id, name] }
    @new_series.each do |brand_id, name|
      ids[[brand_id, name.downcase]] = db[:brand_series].insert(brand_id: brand_id, name: name, active: true, created_by: user_id)
    end
    ids
  end

  def describe(changes)
    changes.map { |k, (from, to)| "#{k}: #{from.nil? || from == '' ? '—' : from} → #{to.nil? || to == '' ? '—' : to}" }
  end

  # ---- small helpers ----

  # Formula cells whose result was never worked out (a file saved by a tool that doesn't calculate) hold an empty
  # <v/>, which the Excel reader can't handle — drop those empty results; the formulas don't matter to the import.
  def without_empty_results(bytes)
    input = Zip::File.open_buffer(StringIO.new(bytes))
    output = Zip::OutputStream.write_buffer do |zip|
      input.each do |entry|
        next if entry.directory?

        content = entry.get_input_stream.read
        content = content.gsub(%r{<v\s*/>|<v>\s*</v>}, '') if entry.name.start_with?('xl/worksheets/')
        zip.put_next_entry(entry.name)
        zip.write(content)
      end
    end
    output.string
  end

  def field(cells, prefix)
    key = cells.keys.find { |h| h.downcase.start_with?(prefix.downcase) }
    key && cells[key]
  end

  def text(value)
    value = value.to_i if value.is_a?(Float) && value == value.floor
    value.to_s.strip
  end

  def whole(value)
    return value.round if value.is_a?(Numeric)

    cleaned = value.to_s.gsub(/[₹,\s]|rs\.?/i, '')
    Float(cleaned, exception: false)&.round
  end

  def gst_rate(value)
    number = value.is_a?(Numeric) ? value : Float(value.to_s.delete('%').strip, exception: false)
    return nil unless number

    number *= 100 if number.positive? && number < 1 # 0.18 → 18
    GST_RATES.include?(number.round) ? number.round : nil
  end

  def yes_no(value)
    case text(value).downcase
    when '' then nil
    when 'yes', 'y', 'true' then true
    when 'no', 'n', 'false' then false
    else :invalid
    end
  end

  def link?(value)
    value.match?(%r{\Ahttps?://\S+\z}i)
  end

  def plain(value)
    value.is_a?(BigDecimal) ? value.to_f : value
  end

  def unique_slug(name, taken)
    base = name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '').presence || 'item'
    slug = base
    n = 1
    slug = "#{base}-#{n += 1}" while taken.include?(slug)
    taken << slug
    slug
  end

  def brand_code(name)
    base = name.upcase.gsub(/[^A-Z]/, '')[0, 3].presence || 'BR'
    code = base
    n = 1
    code = "#{base}#{n += 1}" while @taken_brand_codes.include?(code)
    @taken_brand_codes << code
    code
  end

  def problem(sheet, row, messages)
    Array(messages).each { |m| @errors << { sheet: SHEETS[sheet], row: row, message: m } }
    nil
  end

  def skipped_example(sheet, row)
    ((@examples ||= {})[sheet] ||= []) << row
    nil
  end

  def note(message)
    @warnings << message
    nil
  end

  # one warning per kind, with a count, instead of hundreds of the same line
  def warn_once(kind, message)
    @warn_counts ||= {}
    first, count = @warn_counts[kind]
    @warn_counts[kind] = [first || message, (count || 0) + 1]
  end
end
