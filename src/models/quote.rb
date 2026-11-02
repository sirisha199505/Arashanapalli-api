class App::Models::Quote < Sequel::Model
  # draft (made by staff, not shared yet) → sent (shared with the customer, or their website request) → contacted
  # → accepted / lost. Expired isn't stored: an in-progress quotation past its valid-until date shows as expired.
  STATUSES = %w[draft sent contacted accepted lost].freeze
  IN_PROGRESS = %w[draft sent contacted].freeze
  SOURCES = %w[online walk_in phone whatsapp].freeze
  CUSTOMER_TYPES = %w[B2C B2B].freeze
  VALID_DAYS = Integer(ENV.fetch('QUOTE_VALID_DAYS', 15))
  GSTIN_RE = /\A\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\z/
  # no 0/O, 1/I/L, U: easy to read out on the phone and to type
  ID_CHARS = '23456789ABCDEFGHJKMNPQRSTVWXYZ'.chars.freeze

  # A new quotation ID: AT-<yymm>-<5 random characters>, e.g. AT-2611-7K3P9.
  # The random part means nobody can open someone else's quotation by guessing IDs.
  def self.generate_number
    loop do
      number = "AT-#{Time.now.strftime('%y%m')}-#{Array.new(5) { ID_CHARS.sample(random: SecureRandom) }.join}"
      return number unless where(base_number: number).any?
    end
  end

  # AT-2611-7K3P9 for the original, AT-2611-7K3P9-001 for its first revised version …
  def self.number_for(base, version)
    version.to_i.zero? ? base : format('%s-%03d', base, version)
  end

  # Only the newest version of each quotation — a quotation and its -00N versions are one conversation with the customer
  def self.latest
    where(id: db[:quotes].select { max(id) }.group(:base_number))
  end

  # what a staff member may see: Limited sales only their own (assigned to or created by them)
  def self.visible_to(user, ds = dataset)
    user&.limited? ? ds.where(Sequel.|({ assigned_to: user.id }, { created_by: user.id })) : ds
  end

  def self.find_by_number(number)
    self[quote_number: number.to_s.strip.upcase]
  end

  # statuses from earlier versions of the app (rows older code may still write until it's redeployed)
  LEGACY_STATUSES = { 'new' => 'sent', 'open' => 'sent', 'won' => 'accepted' }.freeze

  def before_validation
    self.status = LEGACY_STATUSES.fetch(status, status) || 'draft'
    # the contacted switch and the status stay in step
    if column_changed?(:status) && status == 'contacted' then self.contacted = true
    elsif contacted && %w[draft sent].include?(status) then self.status = 'contacted'
    elsif !contacted && status == 'contacted' then self.status = 'sent'
    end
    self.source ||= 'online'
    self.customer_type ||= 'B2C'
    self.version ||= 0
    self.valid_until ||= Date.today + VALID_DAYS
    self.gstin = gstin.to_s.strip.upcase.presence
    self.company_name = company_name.to_s.strip.presence
    self.base_number ||= quote_number
    super
  end

  def validate
    super
    validates_presence [:quote_number, :customer_name, :customer_phone]
    validates_unique :quote_number
    validates_includes STATUSES, :status
    validates_includes SOURCES, :source
    validates_includes CUSTOMER_TYPES, :customer_type
    errors.add(:items, "can't be empty") if items.to_a.empty?
    errors.add(:gstin, 'is not a valid GSTIN') if gstin && !gstin.match?(GSTIN_RE)
    errors.add(:company_name, 'is required for a business (B2B) quotation') if customer_type == 'B2B' && company_name.nil?
  end

  def expired?
    IN_PROGRESS.include?(status) && valid_until && valid_until < Date.today
  end

  # All versions of this quotation (the original and every -00N), oldest first
  def versions
    self.class.where(base_number: base_number).order(:version).select(:id, :quote_number, :version, :total, :status, :created_at).all
  end

  # the status to show: expired once an in-progress quotation is past its validity
  def display_status
    expired? ? 'expired' : status
  end

  def to_pos
    super.merge('expired' => expired?, 'display_status' => display_status)
  end

  # What a customer sees when looking a quotation up by its ID: no internal notes, phone partly hidden
  def public_view
    {
      quote_number: quote_number, version: version, created_at: created_at, valid_until: valid_until, expired: expired?,
      status: status, display_status: display_status, customer_name: customer_name, customer_phone: "******#{customer_phone.to_s[-4..]}",
      customer_city: customer_city, company_name: company_name, gstin: gstin,
      items: items.to_a.map { |i| i.to_h.except('list_price', 'overridden') }, subtotal: subtotal, gst: gst, total: total,
      versions: versions.map { |v| { quote_number: v.quote_number, total: v.total, created_at: v.created_at } }
    }
  end
end
