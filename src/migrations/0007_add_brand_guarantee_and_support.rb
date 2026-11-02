require 'json'

Sequel.migration do
  # Quotation comparison weighs benefits and support: brands get 'guarantee' and 'support' in their specs.
  # SAMPLE starting terms by class (tier) — replace with each brand's real terms in the admin. Existing values are kept.
  up do
    {
      'Premium' => { 'guarantee' => 'Manufacturer replacement for any defect', 'support' => 'Brand service network + installation help' },
      'Standard' => { 'guarantee' => 'Manufacturer replacement for defects', 'support' => 'Dealer service + installation help' },
      'Economy' => { 'guarantee' => 'Store replacement within 6 months', 'support' => 'In-store support at Arashanapalli' }
    }.each do |tier, terms|
      # sample terms first, so any value already in specs wins
      from(:brands).where(tier: tier).update(specs: Sequel.lit('?::jsonb || specs', terms.to_json))
    end
  end

  down do
    from(:brands).update(specs: Sequel.lit("specs - 'guarantee' - 'support'"))
  end
end
