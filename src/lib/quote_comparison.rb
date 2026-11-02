# Compares saved quotations (with the prices actually quoted, overrides included) on price, benefits (warranty,
# guarantee), quality, savings and support — the same rules as the website's comparison (src/utils/quoteCompare.js).
module QuoteComparison
  MAX = 3
  TIER_RANK = { 'Premium' => 3, 'Standard' => 2, 'Economy' => 1 }.freeze
  TIERS = %w[Premium Standard Economy].freeze

  module_function

  # '5 years' → 5, 'Up to 30 years' → 30, '2–5 years' → 2, '18 months' → 1.5, 'Lifetime …' → 25, shelf life → nil
  def warranty_years(text)
    t = text.to_s.downcase
    return nil if t.empty? || t.include?('shelf life')
    return 25 if t.include?('lifetime')
    numbers = t.scan(/\d+(?:\.\d+)?/).map(&:to_f)
    return nil if numbers.empty?
    n = t.include?('up to') ? numbers.max : numbers.first
    t.include?('month') ? n / 12 : n
  end

  # Comparable only when every quotation has the same products in the same quantities — only brands / prices differ
  def same_products?(quotes)
    quotes.map { |q| q.items.to_a.map { |i| [i['product_id'], i['quantity'].to_i] }.sort }.uniq.size == 1
  end

  def years(n)
    n >= 25 ? 'lifetime' : "#{n.round(1).to_s.sub(/\.0\z/, '')} yr#{n == 1 ? '' : 's'}"
  end

  def evaluate(quote, brands)
    lines = quote.items.to_a.select { |i| i['amount'] }
    amount = [lines.sum { |l| l['amount'] }, 1].max
    with_brand = lines.map { |l| [l, brands[l['brand_id']]] }.select { |_, b| b }
    warranties = with_brand.filter_map { |l, b| (y = warranty_years(b.specs.to_h['warranty'])) && [l, y] }
    used = with_brand.map(&:last).uniq
    {
      quote: quote, total: quote.total.to_i, missing: quote.items.to_a.size - lines.size,
      quality: with_brand.sum { |l, b| TIER_RANK.fetch(b.tier, 2) * l['amount'] } / amount.to_f,
      tiers: TIERS.to_h { |t| [t, with_brand.select { |_, b| b.tier == t }.sum { |l, _| l['amount'] } / amount.to_f] },
      warranty: warranties.empty? ? nil : {
        min: warranties.map(&:last).min, max: warranties.map(&:last).max,
        avg: warranties.sum { |l, y| y * l['amount'] } / [warranties.sum { |l, _| l['amount'] }, 1].max.to_f
      },
      guarantees: used.filter_map { |b| b.specs.to_h['guarantee'] }.uniq,
      supports: used.filter_map { |b| b.specs.to_h['support'] }.uniq,
      brands: used
    }
  end

  # Each result gains criteria [{ label, value, note, tone: :pro / :con / nil }], badges and savings
  def compare(quotes)
    brand_ids = quotes.flat_map { |q| q.items.to_a.map { |i| i['brand_id'] } }.compact.uniq
    brands = App::Models::Brand.where(id: brand_ids).to_hash(:id)
    results = quotes.map { |q| evaluate(q, brands) }
    complete = results.select { |r| r[:missing].zero? }
    several = complete.size > 1
    min_total, max_total = complete.map { |r| r[:total] }.minmax
    worst_w, best_w = complete.filter_map { |r| r[:warranty]&.dig(:avg) }.minmax
    worst_q, best_q = complete.map { |r| r[:quality] }.minmax
    spread = ->(v, lo, hi) { hi && lo && hi > lo ? (v - lo) / (hi - lo).to_f : 1 }
    balance = lambda do |r|
      # price counts in proportion (₹3 dearer ≈ as good), the others relative to the best and worst on offer
      0.4 * (r[:total].positive? ? min_total.to_f / r[:total] : 0) + 0.25 * spread.(r[:quality], worst_q, best_q) +
        0.2 * (r[:warranty] ? spread.(r[:warranty][:avg], worst_w, best_w) : 0) +
        0.15 * (r[:brands].size <= 1 ? 1 : r[:brands].size == 2 ? 0.6 : 0.3)
    end
    recommended = several ? complete.max_by(&balance) : nil

    results.map do |r|
      ok = complete.include?(r)
      is = ->(v, target) { several && ok && v == target }
      savings = ok && several ? max_total - r[:total] : 0
      w = r[:warranty]
      quality_label = r[:quality] >= 2.6 ? 'Mostly premium brands' : r[:quality] >= 1.8 ? 'Mostly standard brands' : 'Mostly budget brands'
      price_note = if !ok then "#{r[:missing]} item(s) not priced"
                   elsif is.(r[:total], min_total) then 'Lowest price'
                   elsif several then "#{QuotePdf.inr(r[:total] - min_total)} more than the cheapest"
                   else ''
                   end
      criteria = [
        { key: 'price', label: 'Price (incl. GST)', value: QuotePdf.inr(r[:total]), note: price_note,
          tone: !ok ? :con : is.(r[:total], min_total) ? :pro : is.(r[:total], max_total) ? :con : nil },
        { key: 'benefits', label: 'Benefits (warranty, guarantee)', value: w ? (w[:min] == w[:max] ? years(w[:min]) : "#{years(w[:min])} – #{years(w[:max])}") : 'Not stated',
          note: [w && "avg #{years(w[:avg])}", r[:guarantees].join('; ').presence].compact.join(' · '),
          tone: !w ? :con : is.(w[:avg], best_w) ? :pro : is.(w[:avg], worst_w) || w[:min] <= 1 ? :con : nil },
        { key: 'quality', label: 'Quality', value: r[:brands].empty? ? '—' : quality_label,
          note: TIERS.select { |t| r[:tiers][t].positive? }.map { |t| "#{(r[:tiers][t] * 100).round}% #{t}" }.join(' · '),
          tone: r[:brands].empty? ? nil : is.(r[:quality], best_q) ? :pro : is.(r[:quality], worst_q) ? :con : nil },
        { key: 'savings', label: 'Savings', value: ok && several ? QuotePdf.inr(savings) : '—',
          note: ok && several ? (savings.positive? ? "#{(savings * 100.0 / max_total).round}% less than the costliest" : 'The costliest option') : '',
          tone: ok && several ? (savings.positive? ? :pro : :con) : nil },
        { key: 'support', label: 'Support', value: "#{r[:brands].size} brand#{r[:brands].size == 1 ? '' : 's'}",
          note: [r[:brands].size == 1 ? 'One point of contact' : 'Several service contacts', *r[:supports]].join(' · '),
          tone: r[:brands].size == 1 ? :pro : r[:brands].size >= 3 ? :con : nil }
      ]
      badges = [
        ('Recommended' if r.equal?(recommended)), ('Best price' if is.(r[:total], min_total)),
        ('Longest warranty' if w && is.(w[:avg], best_w)), ('Best quality' if is.(r[:quality], best_q))
      ].compact
      r.merge(criteria: criteria, badges: badges, savings: savings)
    end
  end
end
