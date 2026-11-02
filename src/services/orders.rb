class App::Services::Orders < App::Services::Base
  def model; Order; end

  def self.fields
    {
      save: [:status, :payment_status, :amount_paid, :delivery_on, :notes, :assigned_to]
    }
  end

  # filters: search (order / quotation ID, phone, name, company), status, payment_status, from, to (dates)
  def list
    ds = Order.visible_to(staff)
    if qs[:search].present?
      term = qs[:search].strip
      digits = term.gsub(/\D/, '')
      cond = Sequel.ilike(:order_number, "%#{term}%") | Sequel.ilike(:quote_number, "%#{term}%") |
             Sequel.ilike(:customer_name, "%#{term}%") | Sequel.ilike(:company_name, "%#{term}%")
      cond |= Sequel.like(:customer_phone, "%#{digits.last(10)}%") if digits.length >= 4
      ds = ds.where(cond)
    end
    ds = ds.where(status: qs[:status]) if Order::STATUSES.include?(qs[:status])
    ds = ds.where(status: %w[confirmed processing ready]) if qs[:status] == 'active'
    ds = ds.where(payment_status: qs[:payment_status]) if Order::PAYMENT_STATUSES.include?(qs[:payment_status])
    from = date(qs[:from])
    to = date(qs[:to])
    ds = ds.where { created_at >= from } if from
    ds = ds.where { created_at < to + 1 } if to
    count = ds.count
    all = Order.visible_to(staff)
    counts = { all: all.count, active: all.where(status: %w[confirmed processing ready]).count,
               **Order::STATUSES.to_h { |s| [s.to_sym, all.where(status: s).count] },
               unpaid: all.exclude(status: 'cancelled').exclude(payment_status: 'paid').count }
    rows = ds.order(Sequel.desc(:created_at)).offset(offset).limit(limit).all
    return_success(rows.map(&:to_pos), total_pages: (count / page_size.to_f).ceil, total: count, counts: counts)
  end

  def get
    return_success(item.to_pos)
  end

  def update
    data = data_for(:save)
    data.delete('assigned_to') if staff.limited?
    data['delivery_on'] = date(data['delivery_on']) if data.key?('delivery_on')
    item.set_fields(data, data.keys)
    item.valid? # payment status follows the amount before the changes are recorded
    changes = Audit.changes_of(item)
    save(item) do |o|
      Audit.log(:order, o.id, :updated, ref: o.order_number, changes: changes) if changes.any?
      return_success(o.to_pos)
    end
  end

  private

  def staff
    App.cu.user_obj
  end

  def item(id = rp[:id])
    @item ||= Order.visible_to(staff).where(id: id.to_i).first || return_errors!('No order found', 404)
  end

  def date(value)
    value.present? ? Date.parse(value.to_s) : nil
  rescue Date::Error
    nil
  end
end
