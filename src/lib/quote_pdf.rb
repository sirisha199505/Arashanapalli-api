require 'prawn'
require 'prawn/table'
require 'rqrcode_core'
require 'erb'

# Branded PDFs for quotations and quotation comparisons (A4): logo and shop details, the quotation, GST split,
# validity and terms. DejaVu Sans is bundled because the PDF's built-in fonts have no ₹ sign.
module QuotePdf
  ASSETS = File.expand_path('../assets', __dir__)
  RED = 'A82024'
  INK = '1A1A1A'
  MUTED = '626262'
  LINE = 'E5E2DC'
  TINT = 'F7F1EE'
  GREEN = '1E7B4F'
  QR_SIZE = 92

  module_function

  # ₹1,23,456 — Indian digit grouping
  def inr(amount)
    digits = amount.to_i.abs.to_s
    grouped = digits.length > 3 ? "#{digits[0...-3].reverse.scan(/\d{1,2}/).join(',').reverse},#{digits[-3..]}" : digits
    "#{'-' if amount.to_i.negative?}₹#{grouped}"
  end

  def date(value)
    value && (value.respond_to?(:strftime) ? value : Date.parse(value.to_s)).strftime('%d %b %Y')
  end

  def track_url(number)
    Company::SITE_URL.empty? ? nil : "#{Company::SITE_URL}/track/#{number}"
  end

  # CGST + SGST for buyers in the shop's state (or with no GSTIN), IGST for other states
  def gst_lines(quote)
    other_state = quote.gstin.to_s.length == 15 && quote.gstin[0, 2] != Company::STATE_CODE
    return [['IGST (18%)', quote.gst]] if other_state
    half = quote.gst.to_i / 2
    [['CGST (9%)', half], ['SGST (9%)', quote.gst.to_i - half]]
  end

  def document
    pdf = Prawn::Document.new(page_size: 'A4', margin: [36, 36, 54, 36], info: { Title: Company::NAME, Creator: Company::NAME })
    pdf.font_families.update('DejaVu' => { normal: File.join(ASSETS, 'fonts/DejaVuSans.ttf'), bold: File.join(ASSETS, 'fonts/DejaVuSans-Bold.ttf') })
    pdf.font('DejaVu')
    pdf.default_leading 1
    pdf
  end

  # logo, shop name and details on the left; the document title and its facts on the right
  def header(pdf, title, facts)
    top = pdf.cursor
    logo = File.join(ASSETS, 'logo.jpg')
    pdf.image(logo, at: [0, top], width: 44) if File.exist?(logo)
    pdf.bounding_box([54, top], width: 270) do
      pdf.text Company::NAME, size: 16, style: :bold, color: RED
      pdf.text Company::TAGLINE, size: 8, color: MUTED
      pdf.move_down 3
      pdf.text Company::ADDRESS, size: 8, color: INK
      contact = [Company::PHONE, Company::EMAIL.presence, (Company::GSTIN.empty? ? nil : "GSTIN #{Company::GSTIN}")].compact.join(' · ')
      pdf.text contact, size: 8, color: INK
    end
    pdf.bounding_box([pdf.bounds.width - 200, top], width: 200) do
      pdf.text title, size: 15, style: :bold, align: :right
      facts.each { |label, value| pdf.text "<color rgb='#{MUTED}'>#{label}</color>  #{value}", size: 8.5, align: :right, inline_format: true }
    end
    pdf.move_down 10
    pdf.stroke_color RED
    pdf.line_width 1.5
    pdf.stroke_horizontal_rule
    pdf.move_down 12
  end

  def footer(pdf)
    pdf.repeat(:all) do
      pdf.bounding_box([0, -14], width: pdf.bounds.width, height: 20) do
        pdf.text "#{Company::NAME} · #{Company::PHONE} · This is a computer-generated quotation.", size: 7, color: MUTED, align: :center
      end
    end
    pdf.number_pages 'Page <page> of <total>', at: [pdf.bounds.right - 80, -14], width: 80, align: :right, size: 7, color: MUTED
  end

  def terms(pdf, valid_until)
    pdf.move_down 14
    pdf.text 'Terms & conditions', size: 9, style: :bold
    pdf.move_down 3
    Company::TERMS.each_with_index { |t, i| pdf.text "#{i + 1}. #{t}", size: 7.5, color: MUTED }
    pdf.move_down 4
    pdf.text "Valid until #{date(valid_until)}.", size: 7.5, style: :bold, color: RED
  end

  def bill_to(pdf, quote)
    lines = [
      "<b>#{escape(quote.customer_name)}</b>",
      [quote.company_name.presence, (quote.gstin.presence && "GSTIN #{quote.gstin}")].compact.map { |s| escape(s) }.join(' · ').presence,
      ["+91 #{quote.customer_phone}", quote.customer_email.presence, quote.customer_city.presence].compact.map { |s| escape(s) }.join(' · ')
    ].compact
    pdf.text 'Bill to', size: 8, color: MUTED
    lines.each { |l| pdf.text l, size: 9, inline_format: true }
    pdf.move_down 10
  end

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def table_style(table)
    table.cells.border_color = LINE
    table.cells.borders = [:bottom]
    table.cells.padding = [5, 4]
    table.row(0).font_style = :bold
    table.row(0).text_color = MUTED
    table.row(0).size = 7.5
    table.row(0).borders = [:bottom]
    table.row(0).border_width = 1
  end

  # One quotation
  def quote(quote)
    pdf = document
    header(pdf, 'QUOTATION', [
      ['Quotation ID', quote.quote_number], ['Date', date(quote.created_at)], ['Valid until', date(quote.valid_until)],
      (['Version', quote.version.to_s] if quote.version.to_i.positive?)
    ].compact)
    bill_to(pdf, quote)

    rows = [['#', 'Item code', 'Description', 'Qty', 'Rate', 'Amount']]
    quote.items.to_a.each_with_index do |i, n|
      details = [i['warranty'] && "Warranty #{i['warranty']}", i['benefits'], i['note']].compact.join(' · ')
      alternatives = Array(i['alternatives']).map { |alt| "#{alt['brand_name']} #{inr(alt['unit_price'])}#{" (#{alt['warranty']})" if alt['warranty']}" }
      description = [
        i['product_name'], i['brand_name'] || 'Brand to be confirmed', details.presence,
        ("Alternatives: #{alternatives.join(' · ')}" if alternatives.any?)
      ].compact.join("\n")
      rows << [n + 1, i['dynamic_code'] || i['product_code'], description, "#{i['quantity']} #{i['unit']}",
               i['unit_price'] ? inr(i['unit_price']) : 'On request', i['amount'] ? inr(i['amount']) : '—']
    end
    pdf.table(rows, header: true, width: pdf.bounds.width, column_widths: { 0 => 20, 1 => 82, 3 => 58, 4 => 64, 5 => 70 }, cell_style: { size: 8.5 }) do |t|
      table_style(t)
      t.columns(3..5).align = :right
      t.column(1).font = 'DejaVu'
      t.column(1).size = 7.5
    end

    pdf.move_down 8
    pdf.start_new_page if pdf.cursor < QR_SIZE + 40 # the totals and the payment QR stay together
    top = pdf.cursor
    totals = [['Subtotal', inr(quote.subtotal)], *gst_lines(quote).map { |l, v| [l, inr(v)] }, ['Total', inr(quote.total)]]
    pdf.table(totals, position: :right, column_widths: [110, 90], cell_style: { size: 9, borders: [], padding: [2, 4] }) do |t|
      t.columns(1).align = :right
      t.row(-1).font_style = :bold
      t.row(-1).size = 11
      t.row(-1).borders = [:top]
      t.row(-1).border_color = INK
      t.row(-1).padding = [5, 4, 2, 4]
    end
    below_totals = pdf.cursor
    pdf.move_cursor_to [below_totals, payment(pdf, quote, top)].min

    url = track_url(quote.quote_number)
    if url
      pdf.move_down 8
      pdf.text "View this quotation online: <link href='#{url}'><color rgb='#{RED}'>#{url}</color></link>", size: 8, inline_format: true
    end
    terms(pdf, quote.valid_until)
    footer(pdf)
    pdf.render
  end

  # A QR code for the exact total can be paid only while the quotation stands: priced, not lost, not expired
  def payable?(quote)
    Company::UPI_ID.present? && quote.total.to_i.positive? && quote.items.to_a.all? { |i| i['unit_price'] } &&
      %w[draft sent contacted accepted].include?(App::Models::Quote::LEGACY_STATUSES.fetch(quote.status, quote.status)) && !quote.expired?
  end

  # upi://pay link for the quotation's total: any UPI app opens it with the payee, amount and quotation ID filled in
  def upi_link(quote)
    params = { pa: Company::UPI_ID, pn: Company::UPI_NAME, am: format('%.2f', quote.total.to_i), cu: 'INR', tn: "Quotation #{quote.quote_number}" }
    # '@' stays as it is in the UPI ID: some UPI apps don't read %40
    "upi://pay?#{params.map { |k, v| "#{k}=#{ERB::Util.url_encode(v).gsub('%40', '@')}" }.join('&')}"
  end

  # "Scan to pay" QR code and bank details, left of the totals (which start at `top`). Returns the y it ends at.
  def payment(pdf, quote, top)
    bank = [['Bank', Company::BANK_NAME], ['Account name', Company::ACCOUNT_NAME], ['Account no.', Company::ACCOUNT_NUMBER], ['IFSC', Company::IFSC]].reject { |_, v| v.empty? }
    qr = payable?(quote)
    return top unless qr || bank.any?

    width = pdf.bounds.width - 220 # the totals take the right 200pt
    pdf.bounding_box([0, top], width: width) do
      start = pdf.cursor
      text_at = 0
      if qr
        qr_code(pdf, upi_link(quote), at: [0, start], size: QR_SIZE)
        text_at = QR_SIZE + 8
      end
      pdf.bounding_box([text_at, start], width: width - text_at) do
        pdf.move_down 6 if qr # line the text up with the code inside the QR's quiet zone
        if qr
          pdf.text 'Scan to pay by UPI', size: 9.5, style: :bold
          pdf.text "#{inr(quote.total)} · Quotation #{quote.quote_number}", size: 8.5, style: :bold, color: RED
          pdf.text "UPI ID: #{Company::UPI_ID}", size: 8
          pdf.text 'GPay, PhonePe, Paytm or any UPI app — the amount and quotation ID fill in by themselves.', size: 7, color: MUTED
        else
          pdf.text 'Payment details', size: 9.5, style: :bold
        end
        if bank.any?
          pdf.move_down 4
          pdf.text 'Bank transfer', size: 8, style: :bold if qr
          bank.each { |label, value| pdf.text "<color rgb='#{MUTED}'>#{label}:</color> #{escape(value)}", size: 8, inline_format: true }
        end
      end
    end
    # whichever ends lower: the text (where the cursor is now) or the QR code
    qr ? [pdf.cursor, top - QR_SIZE].min : pdf.cursor
  end

  # A QR code drawn as vector squares (sharp at any zoom); each row's dark runs are one rectangle so no hairlines show
  def qr_code(pdf, text, at:, size:)
    modules = RQRCodeCore::QRCode.new(text, level: :m).modules
    quiet = 3 # light border the scanner needs, in modules
    cell = size.to_f / (modules.size + 2 * quiet)
    x0, y0 = at
    pdf.fill_color '000000'
    modules.each_with_index do |row, r|
      c = 0
      while c < row.size
        next c += 1 unless row[c]

        run = c
        c += 1 while c < row.size && row[c]
        pdf.fill_rectangle([x0 + (run + quiet) * cell, y0 - (r + quiet) * cell], (c - run) * cell, cell)
      end
    end
  end

  # The same QR code as an SVG for the website: one path, each row's dark runs as one rectangle
  def qr_svg(text, quiet: 3)
    modules = RQRCodeCore::QRCode.new(text, level: :m).modules
    size = modules.size + 2 * quiet
    path = +''
    modules.each_with_index do |row, r|
      c = 0
      while c < row.size
        next c += 1 unless row[c]

        run = c
        c += 1 while c < row.size && row[c]
        path << "M#{run + quiet} #{r + quiet}h#{c - run}v1h-#{c - run}z"
      end
    end
    %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{size} #{size}" shape-rendering="crispEdges"><rect width="#{size}" height="#{size}" fill="#fff"/><path d="#{path}" fill="#000"/></svg>)
  end

  # Up to 3 quotations for the same products: pros / cons on price, benefits, quality, savings and support,
  # then each item's brand and price side by side
  def comparison(quotes, results)
    pdf = document
    header(pdf, 'QUOTATION COMPARISON', [['Date', date(Date.today)], ['Quotations', quotes.size.to_s], ['Valid until', date(quotes.map(&:valid_until).compact.min)]])
    bill_to(pdf, quotes.first)

    recommended = results.find { |r| r[:badges].include?('Recommended') }
    if recommended
      pdf.fill_color TINT
      pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, 30
      pdf.fill_color INK
      pdf.bounding_box([8, pdf.cursor - 6], width: pdf.bounds.width - 16) do
        pdf.text "<b>Recommended: #{recommended[:quote].quote_number}</b> — best balance of price (40%), quality (25%), warranty (20%) and support (15%).", size: 8.5, inline_format: true
      end
      pdf.move_down 14
    end

    mark = { pro: "<color rgb='#{GREEN}'>✓</color> ", con: "<color rgb='#{RED}'>✗</color> " }
    head = ['', *results.map { |r| "<b>#{r[:quote].quote_number}</b>#{r[:badges].any? ? "\n<color rgb='#{RED}'>#{r[:badges].join(' · ')}</color>" : ''}" }]
    rows = [head] + results.first[:criteria].each_index.map do |i|
      [results.first[:criteria][i][:label], *results.map do |r|
        c = r[:criteria][i]
        "#{mark[c[:tone]]}<b>#{escape(c[:value])}</b>#{c[:note].to_s.empty? ? '' : "\n<color rgb='#{MUTED}'>#{escape(c[:note])}</color>"}"
      end]
    end
    pdf.text 'Pros and cons', size: 10, style: :bold
    pdf.move_down 4
    pdf.table(rows, header: true, width: pdf.bounds.width, column_widths: { 0 => 95 }, cell_style: { size: 8, inline_format: true }) do |t|
      table_style(t)
      t.row(0).text_color = INK
      t.column(0).font_style = :bold
    end
    pdf.move_down 4
    pdf.text "<color rgb='#{GREEN}'>✓</color> pro   <color rgb='#{RED}'>✗</color> con · Prices include 18% GST.", size: 7, inline_format: true, color: MUTED

    pdf.move_down 12
    pdf.text 'Item by item', size: 10, style: :bold
    pdf.move_down 4
    items = quotes.first.items.to_a.map { |i| [i['product_id'], i] }
    rows = [['Product', 'Qty', *quotes.map(&:quote_number)]]
    items.each do |product_id, first|
      rows << ["#{first['product_name']}\n#{first['product_code']}", "#{first['quantity']} #{first['unit']}", *quotes.map do |q|
        line = q.items.to_a.find { |i| i['product_id'] == product_id }
        line && line['unit_price'] ? "#{line['brand_name']}\n#{inr(line['unit_price'])} → #{inr(line['amount'])}" : (line ? "#{line['brand_name'] || '—'}\nOn request" : '—')
      end]
    end
    rows << ['Total (incl. GST)', '', *quotes.map { |q| inr(q.total) }]
    pdf.table(rows, header: true, width: pdf.bounds.width, column_widths: { 1 => 55 }, cell_style: { size: 8 }) do |t|
      table_style(t)
      t.row(-1).font_style = :bold
      t.row(-1).borders = [:top]
      t.row(-1).border_color = INK
    end

    terms(pdf, quotes.map(&:valid_until).compact.min)
    footer(pdf)
    pdf.render
  end
end
