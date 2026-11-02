class App::Services::Customers < App::Services::Base
  # Admin: everyone who has sent a quote request, one row per mobile number, most recent first
  def list
    ds = Quote.visible_to(App.cu.user_obj).naked.group(:customer_phone).select(
      :customer_phone,
      Sequel.lit('(array_agg(customer_name ORDER BY created_at DESC))[1]').as(:name),
      Sequel.lit("(array_agg(customer_city ORDER BY created_at DESC) FILTER (WHERE customer_city <> ''))[1]").as(:city),
      Sequel.function(:count).*.as(:quotes),
      Sequel.function(:coalesce, Sequel.function(:sum, :total), 0).as(:total_value),
      Sequel.function(:coalesce, Sequel.function(:sum, Sequel.case({ { status: 'accepted' } => :total }, 0)), 0).as(:won_value),
      Sequel.function(:min, :created_at).as(:first_quote_at),
      Sequel.function(:max, :created_at).as(:last_quote_at)
    )
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.ilike(:customer_name, term) | Sequel.ilike(:customer_phone, term) | Sequel.ilike(:customer_city, term))
    end
    count = ds.count
    rows = ds.order(Sequel.desc(:last_quote_at)).offset(offset).limit(limit).all
    return_success(rows, total_pages: (count / page_size.to_f).ceil)
  end
end
