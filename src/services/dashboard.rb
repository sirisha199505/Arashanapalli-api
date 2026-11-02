class App::Services::Dashboard < App::Services::Base
  # days before today (in IST) that each period starts; 'all' has no start
  PERIOD_DAYS = { 'today' => 0, '7d' => 6, '30d' => 29 }.freeze

  # Admin: headline numbers for the dashboard, for the chosen period
  def show
    mine = Quote.visible_to(App.cu.user_obj, Quote.latest) # one per quotation (its latest version); Limited sales: their own
    quotes = in_period(mine)
    status_counts = quotes.group_and_count(:status).to_hash(:status, :count)
    value = quotes.sum(:total).to_i
    count = quotes.count
    channels = quotes.group(:sent_via)
                     .select(:sent_via, Sequel.function(:count).*.as(:count), Sequel.function(:coalesce, Sequel.function(:sum, :total), 0).as(:value))
                     .naked.all.to_h { |row| [row[:sent_via] || 'unknown', { count: row[:count], value: row[:value].to_i }] }

    return_success(
      period: period,
      quotes: {
        total: count,
        value: value,
        avg_value: count.positive? ? (value / count.to_f).round(2) : 0,
        accepted_value: quotes.where(status: 'accepted').sum(:total).to_i,
        **Quote::STATUSES.to_h { |s| [s.to_sym, status_counts[s] || 0] },
        contacted: quotes.where(contacted: true).count,
        not_contacted: quotes.where(contacted: false, status: Quote::IN_PROGRESS).count
      },
      channels: { whatsapp: channels['whatsapp'] || { count: 0, value: 0 }, email: channels['email'] || { count: 0, value: 0 } },
      customers: {
        total: quotes.select(:customer_phone).distinct.count,
        new: new_customers_count
      },
      catalog: {
        products: Product.where(active: true).count,
        brands: Brand.where(active: true).count,
        categories: Category.where(active: true).count
      },
      orders: orders_summary(count),
      # not limited to the period: open quotations nobody has contacted yet, and follow-ups due
      awaiting_reply: mine.where(status: Quote::IN_PROGRESS, contacted: false).count,
      follow_ups_due: mine.where(status: Quote::IN_PROGRESS).where { follow_up_on <= Date.today }.count,
      expiring_soon: mine.where(status: Quote::IN_PROGRESS).where { (valid_until >= Date.today) & (valid_until <= Date.today + 3) }.count,
      recent: mine.order(Sequel.desc(:created_at)).limit(5).all.map do |q|
        q.values.slice(:id, :quote_number, :customer_name, :customer_phone, :total, :status, :contacted, :created_at)
      end
    )
  end

  private

  # orders in the period (cancelled ones left out of the money), what's still to deliver, and quote → order conversion
  def orders_summary(quote_count)
    mine = Order.visible_to(App.cu.user_obj)
    orders = in_period(mine).exclude(status: 'cancelled')
    value = orders.sum(:total).to_i
    paid = orders.sum(:amount_paid).to_i
    count = orders.count
    {
      total: count, value: value, paid: paid, balance: value - paid,
      to_deliver: mine.where(status: %w[confirmed processing ready]).count,
      conversion: quote_count.positive? ? (count * 100.0 / quote_count).round : 0
    }
  end

  def period
    PERIOD_DAYS.key?(qs[:period]) || qs[:period] == 'all' ? qs[:period] : 'today'
  end

  # Start of the period as a UTC timestamp (created_at is stored in UTC), counting days in India time
  def period_start
    days = PERIOD_DAYS[period]
    return nil unless days

    Sequel.lit("(date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') - make_interval(days => ?)) AT TIME ZONE 'Asia/Kolkata' AT TIME ZONE 'UTC'", days)
  end

  def in_period(ds)
    start = period_start
    start ? ds.where { created_at >= start } : ds
  end

  # customers whose first-ever quote request falls in the period
  def new_customers_count
    firsts = Quote.dataset.group(:customer_phone).select(Sequel.function(:min, :created_at).as(:first_at))
    start = period_start
    firsts = firsts.having { min(created_at) >= start } if start
    firsts.count
  end
end
