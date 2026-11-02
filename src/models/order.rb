class App::Models::Order < Sequel::Model
  STATUSES = %w[confirmed processing ready delivered cancelled].freeze
  PAYMENT_STATUSES = %w[unpaid partial paid].freeze

  def self.generate_number
    loop do
      number = "AO-#{Time.now.strftime('%y%m')}-#{Array.new(5) { App::Models::Quote::ID_CHARS.sample(random: SecureRandom) }.join}"
      return number unless where(order_number: number).any?
    end
  end

  # what a staff member may see: Limited sales only orders of their own quotations
  def self.visible_to(user, ds = dataset)
    user&.limited? ? ds.where(Sequel.|({ assigned_to: user.id }, { created_by: user.id })) : ds
  end

  # A copy of the quotation as accepted (items, prices, customer)
  def self.from_quote(quote, user_id)
    new(
      order_number: generate_number, quote_id: quote.id, quote_number: quote.quote_number, base_number: quote.base_number,
      **quote.values.slice(:customer_name, :customer_phone, :customer_email, :customer_city, :customer_type, :company_name, :gstin,
                           :items, :subtotal, :gst, :total, :assigned_to),
      created_by: user_id
    )
  end

  def before_validation
    self.status ||= 'confirmed'
    self.amount_paid = amount_paid.to_i.clamp(0, total.to_i)
    # payment status follows the amount paid unless set by hand
    unless column_changed?(:payment_status)
      self.payment_status = amount_paid.zero? ? 'unpaid' : amount_paid >= total.to_i ? 'paid' : 'partial'
    end
    super
  end

  def validate
    super
    validates_presence [:order_number, :quote_id, :customer_name, :customer_phone]
    validates_includes STATUSES, :status
    validates_includes PAYMENT_STATUSES, :payment_status
  end

  def to_pos
    super.merge('balance' => total.to_i - amount_paid.to_i)
  end
end
