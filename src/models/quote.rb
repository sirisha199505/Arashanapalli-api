class App::Models::Quote < Sequel::Model
  STATUSES = %w[new contacted won lost].freeze

  def before_validation
    self.status ||= 'new'
    super
  end

  def validate
    super
    validates_presence [:customer_name, :customer_phone]
    validates_includes STATUSES, :status
    errors.add(:items, "can't be empty") if items.to_a.empty?
  end
end
