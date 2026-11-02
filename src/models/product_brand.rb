class App::Models::ProductBrand < Sequel::Model(:product_brands)
  # A brand's own details for one product (price, stock, photo, description); blank = the standard
  unrestrict_primary_key

  STOCK_STATUSES = %w[in_stock low_stock out_of_stock on_order].freeze
  DETAILS = %i[price stock_status stock_qty image description].freeze

  def validate
    super
    validates_presence [:product_id, :brand_id]
    validates_includes STOCK_STATUSES, :stock_status, allow_nil: true, message: 'is not a valid stock status'
    errors.add(:price, 'must be a positive whole number') if price && !price.positive?
    errors.add(:stock_qty, "can't be negative") if stock_qty&.negative?
  end

  # nothing of its own left: the row can go
  def blank?
    DETAILS.all? { |f| self[f].nil? }
  end

  # the website's shape — only what's set
  def as_catalog
    { price: price, stock: stock_status, image: image, description: description }.compact
  end
end
