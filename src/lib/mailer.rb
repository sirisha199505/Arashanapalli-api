# Sends email through the shop's SMTP account (Render environment: EMAIL_SMTP_SERVER, EMAIL_SMTP_PORT,
# EMAIL_DOMAIN, EMAIL_USER, EMAIL_PASSWORD, EMAIL_FROM). Without them, email features say they're switched off.
module Mailer
  module_function

  def configured?
    ENV['EMAIL_SMTP_SERVER'].present? && ENV['EMAIL_USER'].present? && ENV['EMAIL_PASSWORD'].present?
  end

  def deliver(to:, subject:, text:)
    mail = Mail.new
    mail.from = ENV.fetch('EMAIL_FROM', ENV['EMAIL_USER'])
    mail.to = to
    mail.subject = subject
    mail.body = text
    mail.delivery_method :smtp,
                         address: ENV['EMAIL_SMTP_SERVER'], port: ENV.fetch('EMAIL_SMTP_PORT', 587).to_i, domain: ENV['EMAIL_DOMAIN'],
                         user_name: ENV['EMAIL_USER'], password: ENV['EMAIL_PASSWORD'], authentication: 'plain', enable_starttls_auto: true
    mail.deliver!
  end
end
