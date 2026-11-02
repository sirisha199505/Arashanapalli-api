class App::Services::AuditLogs < App::Services::Base
  # Admin: the whole audit trail, newest first. Filters: entity_type, user_id, batch_id (one bulk update), search (ID / code / note), from, to
  def list
    ds = AuditLog.dataset
    ds = ds.where(entity_type: qs[:entity_type]) if qs[:entity_type].present?
    ds = ds.where(user_id: qs[:user_id].to_i) if qs[:user_id].present?
    ds = ds.where(batch_id: qs[:batch_id]) if qs[:batch_id].present?
    if qs[:search].present?
      term = "%#{qs[:search].strip}%"
      ds = ds.where(Sequel.ilike(:ref, term) | Sequel.ilike(:note, term) | Sequel.ilike(:user_name, term))
    end
    from = date(qs[:from])
    to = date(qs[:to])
    ds = ds.where { created_at >= from } if from
    ds = ds.where { created_at < to + 1 } if to
    count = ds.count
    return_success(ds.order(Sequel.desc(:id)).offset(offset).limit(limit).all.map(&:to_pos), total_pages: (count / page_size.to_f).ceil, total: count)
  end

  private

  def date(value)
    value.present? ? Date.parse(value.to_s) : nil
  rescue Date::Error
    nil
  end
end
