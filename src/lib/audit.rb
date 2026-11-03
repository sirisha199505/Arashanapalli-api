# Audit trail: who changed what, when, from → to. Written alongside every change that matters (quotations, orders,
# catalog prices, staff roles) so bulk updates and price overrides can always be traced back to a person.
module Audit
  IGNORED = %i[updated_at updated_by created_at created_by encoded_password current_session_id last_logged_in_at].freeze

  module_function

  # { column: [from, to] } of a model's unsaved changes, without bookkeeping columns (call before saving)
  def changes_of(model)
    model.column_changes.except(*IGNORED).transform_values { |pair| pair.map { |v| plain(v) } }.reject { |_, (from, to)| from == to }
  end

  def plain(value)
    case value
    when Date, Time then value.to_date.iso8601
    when BigDecimal then value.to_f
    when Sequel::Postgres::PGArray then value.to_a
    else value.respond_to?(:to_hash) ? value.to_hash : value
    end
  end

  # batch_id groups the entries of one bulk update
  def log(entity_type, entity_id, action, ref: nil, changes: {}, note: nil, batch_id: nil)
    user = App::Helpers::CurrentUser.user_obj
    App::Models::AuditLog.create(
      entity_type: entity_type.to_s, entity_id: entity_id.to_s, ref: ref, action: action.to_s,
      changes: Sequel.pg_jsonb(changes.as_json), note: note, batch_id: batch_id,
      user_id: user&.id, user_name: user&.full_name || 'Customer (website)'
    )
  end

  # Many entries in one insert (imports): [{ entity_type, entity_id, ref, action, changes, note }]
  def log_many(entries, batch_id:)
    user = App::Helpers::CurrentUser.user_obj
    now = Time.now
    rows = entries.map do |e|
      { entity_type: e[:entity_type].to_s, entity_id: e[:entity_id].to_s, ref: e[:ref], action: e[:action].to_s,
        changes: Sequel.pg_jsonb((e[:changes] || {}).as_json), note: e[:note], batch_id: batch_id,
        user_id: user&.id, user_name: user&.full_name || 'Customer (website)', created_at: now }
    end
    App::Models::AuditLog.dataset.multi_insert(rows, slice: 500) if rows.any?
  end

  # Line-by-line differences between two versions of a quotation: added / removed products,
  # brand, quantity and quoted-price changes — [{ product, change, from, to }]
  def line_changes(old_items, new_items)
    old_by = old_items.to_a.to_h { |i| [i['product_id'] || i[:product_id], i] }
    new_by = new_items.to_a.to_h { |i| [(i['product_id'] || i[:product_id]), i.transform_keys(&:to_s)] }
    changes = []
    new_by.each do |id, now|
      before = old_by[id]
      next changes << { product: now['product_name'], change: 'added', to: "#{now['quantity']} × #{now['brand_name'] || 'no brand'}" } unless before
      { 'brand_name' => 'brand', 'quantity' => 'quantity', 'unit_price' => 'quoted price' }.each do |key, label|
        changes << { product: now['product_name'], change: label, from: before[key], to: now[key] } if before[key] != now[key]
      end
    end
    (old_by.keys - new_by.keys).each { |id| changes << { product: old_by[id]['product_name'], change: 'removed' } }
    changes
  end
end
