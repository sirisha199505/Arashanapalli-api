class App::Models::QuoteActivity < Sequel::Model(:quote_activities)
  KINDS = %w[call whatsapp visit email note version status created].freeze
  # these mean the customer was reached
  CONTACT_KINDS = %w[call whatsapp visit email].freeze

  def validate
    super
    validates_presence [:base_number, :kind]
    validates_includes KINDS, :kind
  end
end
