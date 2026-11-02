class App::Services::Users < App::Services::Base
  def model; User; end

  def self.fields
    {
      save: [:full_name, :email, :phone_number, :role, :active, :password]
    }
  end

  # ---- staff accounts (admin only) ----

  def list
    return_success(model.order(Sequel.desc(:active), :full_name).all.map(&:as_pos))
  end

  def get
    return_success(item.as_pos)
  end

  def create
    data = data_for(:save)
    user = model.new(data.except('password'))
    user.password = data['password']
    save(user) do |u|
      Audit.log(:user, u.id, :created, ref: u.email, note: "#{u.full_name} — #{u.role_name}")
      return_success(u.as_pos)
    end
  end

  # an admin can't lock themself out (remove their own admin role or deactivate themself)
  def update
    data = data_for(:save)
    if item.id == App.cu.id
      return_errors!(role: "You can't change your own role") if data.key?('role') && data['role'].to_i != item.role
      return_errors!(active: "You can't deactivate yourself") if data.key?('active') && [false, 'false'].include?(data['active'])
    end
    password = data.delete('password')
    item.set_fields(data, data.keys)
    item.password = password if password.present?
    # signing in again is required after a password change or deactivation
    item.current_session_id = nil if password.present? || item.column_changed?(:active)
    changes = Audit.changes_of(item)
    changes['password'] = %w[— changed] if password.present? # never the password itself
    save(item) do |u|
      Audit.log(:user, u.id, :updated, ref: u.email, changes: changes, note: u.full_name) if changes.any?
      return_success(u.as_pos)
    end
  end

  # active staff, for "assigned to" choices and the salesperson filter (any staff can read)
  def staff
    return_success(model.where(active: true).order(:full_name).all.map { |u| { id: u.id, full_name: u.full_name, role_name: u.role_name } })
  end

  # ---- the signed-in staff member ----

  def info
    return_success(App.cu.user_obj.as_pos)
  end

  def update_password
    user = App.cu.user_obj
    return_errors!(current_password: 'Wrong password') unless user.password == params[:current_password]
    user.password = params[:new_password]
    save(user) { return_success('Password updated') }
  end
end
