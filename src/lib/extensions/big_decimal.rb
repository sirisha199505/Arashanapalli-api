class BigDecimal
  def as_json(*)
    val = super
    val.is_a?(String) ? val.to_f : val
  end
end