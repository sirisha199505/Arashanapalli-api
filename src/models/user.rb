class App::Models::User < Sequel::Model
  include BCrypt

  # Associations
  # one_to_many :user_properties

  # Role constants
  ROLES = {
    admin: 1,
    rgm: 2,
    gm: 3
  }.freeze

  def admin?
    role == ROLES[:admin]
  end

  def rgm?
    role == ROLES[:rgm]
  end

  def gm?
    role == ROLES[:gm]
  end

  def validate
    super
    validates_presence [:full_name, :email]
    validates_unique(:email) { |ds| ds.where(active: true) }
  end

  def password
    @password ||= Password.new(encoded_password)
  end

  def password=(new_password)
    @password = Password.create(new_password)
    self.encoded_password = @password
  end

  def name
    full_name
  end

  def role_name
    case role
    when ROLES[:admin]
      "Admin"
    when ROLES[:rgm]
      "RGM"
    when ROLES[:gm]
      "GM"
    else
      "Unknown"
    end
  end

  def generate_reset_token!
    self.reset_token = SecureRandom.urlsafe_base64
    self.reset_sent_at = Time.now
    save
  end

  def send_password_reset_email(base_url)
    generate_reset_token!

    user_email = self.email
    user_name = self.full_name
    reset_url = "#{base_url}/reset_password?token=#{CGI.escape(reset_token)}"

    mail = Mail.new do
      from    ENV.fetch('EMAIL_FROM', 'noreply@example.com')
      to      user_email
      subject 'Reset your password'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Reset your password</h1>
            <p>Hello #{user_name},</p>
            <p>We received a request to reset your password. Click the link below to reset your password:</p>
            <p><a href="#{reset_url}">Reset your password</a></p>
            <p>If you did not request a password reset, please ignore this email.</p>
            <p>Thank you,<br/>Support Team</p>
          </body>
          </html>
        HTML
      end
    end

    mail.deliver!
  end

  def valid_property_ids
    if admin?
      App::Models::Property.where(client_id: client_id).select_map(:id)
    else
      property_ids || []
    end
  end

  def properties
    property_ids || []
  end

  def as_pos
    as_json(only:
      [:email, :full_name, :phone_number, :role, :id, :active, :created_at, :updated_at, :last_logged_in_at, :parent_id]
    ).merge!(role_name: role_name, property_count: properties.length)
  end
end
