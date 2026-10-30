class App::Services::Dashboard < App::Services::Base
  # days before today (in IST) that each period starts; 'all' has no start
  PERIOD_DAYS = { 'today' => 0, '7d' => 6, '30d' => 29 }.freeze

  # Admin: headline numbers for the dashboard, for the chosen period
  def show
    quotes = in_period(Quote.dataset)
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
        won_value: quotes.where(status: 'won').sum(:total).to_i,
        **Quote::STATUSES.to_h { |s| [s.to_sym, status_counts[s] || 0] }
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
      # not limited to the period: requests still waiting for a first reply
      awaiting_reply: Quote.where(status: 'new').count,
      recent: Quote.order(Sequel.desc(:created_at)).limit(5).all.map do |q|
        q.values.slice(:id, :quote_number, :customer_name, :customer_phone, :total, :status, :created_at)
      end
    )
  end

  private

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
