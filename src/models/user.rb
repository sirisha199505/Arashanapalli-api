class App::Models::User < Sequel::Model
  include BCrypt

  # Staff roles
  #   admin   — everything: staff accounts, catalog, all quotations, prices
  #   sales   — all quotations; can create, edit and override prices; orders
  #   limited — only quotations assigned to or created by them; list prices only
  ROLES = { admin: 1, sales: 2, limited: 3 }.freeze
  ROLE_NAMES = { 1 => 'Admin', 2 => 'Sales', 3 => 'Limited sales' }.freeze
  MIN_PASSWORD = 8

  def admin? = role == ROLES[:admin]
  def sales? = role == ROLES[:sales]
  def limited? = role == ROLES[:limited]
  def staff? = active && ROLE_NAMES.key?(role)

  # may set their own prices on quotation lines
  def can_edit_prices? = admin? || sales?

  def validate
    super
    validates_presence [:full_name, :email]
    validates_format(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, :email, message: 'is not a valid email')
    validates_unique(:email) { |ds| ds.where(active: true) }
    validates_includes ROLE_NAMES.keys, :role, message: 'must be Admin, Sales or Limited sales'
    errors.add(:password, "must be at least #{MIN_PASSWORD} characters") if @password_too_short
    errors.add(:password, 'is required') if new? && encoded_password.blank?
  end

  def before_validation
    self.email = email.to_s.strip.downcase
    super
  end

  def password
    @password ||= Password.new(encoded_password)
  end

  def password=(new_password)
    @password_too_short = new_password.to_s.length < MIN_PASSWORD
    return if @password_too_short

    @password = Password.create(new_password)
    self.encoded_password = @password
  end

  def name
    full_name
  end

  def role_name
    ROLE_NAMES.fetch(role, 'Unknown')
  end

  def as_pos
    as_json(only: [:id, :email, :full_name, :phone_number, :role, :active, :created_at, :updated_at, :last_logged_in_at])
      .merge!('role_name' => role_name)
  end
end
