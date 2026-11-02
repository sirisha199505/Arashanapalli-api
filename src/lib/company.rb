# The shop's details for quotations and PDFs. Override any of them with environment variables on Render.
module Company
  NAME = ENV.fetch('COMPANY_NAME', 'Arashanapalli Traders')
  TAGLINE = ENV.fetch('COMPANY_TAGLINE', 'Hardware | Interior Products · Since 1970')
  ADDRESS = ENV.fetch('COMPANY_ADDRESS', 'Door No: 3-2-115, General Bazar, Near Anjali Cinema, Secunderabad, Telangana 500003')
  PHONE = ENV.fetch('COMPANY_PHONE', '+91 98851 65727')
  EMAIL = ENV.fetch('COMPANY_EMAIL', '')
  GSTIN = ENV.fetch('COMPANY_GSTIN', '') # the shop's own GSTIN — shown on PDFs once set
  STATE_CODE = ENV.fetch('COMPANY_STATE_CODE', '36') # Telangana: buyers here pay CGST + SGST, others IGST
  SITE_URL = ENV.fetch('SITE_URL', '').chomp('/') # the website, for "track your quotation" links on PDFs

  # PLACEHOLDER terms — replace with the shop's real terms (QUOTE_TERMS, one term per line).
  TERMS = ENV['QUOTE_TERMS']&.split("\n")&.map(&:strip)&.reject(&:empty?) || [
    'Prices include GST at 18% as shown.',
    'This quotation is valid until the date shown above; prices may change after that.',
    'Delivery from our Secunderabad store; delivery charges extra unless agreed in writing.',
    'Payment: as agreed at the time of order.',
    'Warranty and guarantee as per each brand’s terms. Goods once sold are not taken back except for manufacturing defects.'
  ].freeze
end
