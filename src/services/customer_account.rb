class App::Services::CustomerAccount < App::Services::Base
  # Customers sign in with a 6-digit code emailed to them, then see every quotation made with that email.
  CODE_MINUTES = 10
  MAX_TRIES = 5
  MAX_CODES_PER_HOUR = 5
  SESSION_DAYS = 30
  EMAIL_RE = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  def request_code
    email = email_param
    unless Mailer.configured? || App.development?
      return_errors!('Email sign-in is not switched on yet — use your Quotation ID to see a quotation', 503)
    end
    recent = CustomerLogin.where(email: email).where { created_at > Time.now - 3600 }.count
    return_errors!('Too many codes asked for — please try again in an hour', 429) if recent >= MAX_CODES_PER_HOUR

    code = format('%06d', SecureRandom.random_number(1_000_000))
    CustomerLogin.create(email: email, code_digest: BCrypt::Password.create(code), expires_at: Time.now + CODE_MINUTES * 60, created_ip: App.cu.ip)
    emailed = Mailer.configured?
    if emailed
      Mailer.deliver(to: email, subject: "#{code} is your #{Company::NAME} sign-in code",
                     text: "Your sign-in code is #{code}. It works for #{CODE_MINUTES} minutes.\n\nUse it to see your quotations from #{Company::NAME}.\nIf you didn't ask for this, ignore this email.")
    else
      App.logger.info("[development] sign-in code for #{email}: #{code}")
    end
    # the same answer whether or not this email has quotations; emailed: false only on a developer's computer with
    # no email account set up — the code is then in the backend's terminal
    return_success(sent: true, emailed: emailed, minutes: CODE_MINUTES)
  end

  def verify
    email = email_param
    login = CustomerLogin.where(email: email, used: false).where { expires_at > Time.now }.order(Sequel.desc(:id)).first
    return_errors!('That code has expired — ask for a new one', 401) unless login
    login.update(attempts: login.attempts + 1)
    return_errors!('Too many wrong tries — ask for a new code', 429) if login.attempts > MAX_TRIES
    return_errors!('Wrong code — check the email and try again', 401) unless BCrypt::Password.new(login.code_digest) == params[:code].to_s.strip
    login.update(used: true)
    token = JWT.encode({ email: email, typ: 'customer', exp: (Time.now + SESSION_DAYS * 86_400).to_i }, App::Helpers::CurrentUser::SECRET, 'HS256')
    return_success(token: token, email: email)
  end

  # every quotation (latest version) made with the signed-in customer's email, newest first
  def quotes
    email = signed_in_email!
    rows = Quote.latest.where(Sequel.function(:lower, :customer_email) => email).order(Sequel.desc(:created_at)).all
    return_success(rows.map { |q| q.public_view.except(:items).merge(item_count: q.items.to_a.size) })
  end

  private

  def email_param
    email = params&.dig(:email).to_s.strip.downcase
    return_errors!(email: 'Enter a valid email') unless email.match?(EMAIL_RE)
    email
  end

  def signed_in_email!
    payload = JWT.decode(App.cu.token.to_s, App::Helpers::CurrentUser::SECRET, true, { algorithm: 'HS256' })[0]
    return_errors!('Please sign in again', 401) unless payload['typ'] == 'customer' && payload['email'].present?
    payload['email']
  rescue JWT::DecodeError
    return_errors!('Please sign in again', 401)
  end
end
