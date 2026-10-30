class App::Services::Users < App::Services::Base
  def model; User; end

  RESET_TOKEN_EXPIRATION_TIME = 2 * 60 * 60 

  def list
    ds = model.order(Sequel.desc(:created_at))
    if qs[:search].present?
      search_term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.ilike(:full_name, search_term)).or(Sequel.ilike(:phone_number, search_term))
    end
    if App.cu.user_obj.rgm?
      ds = ds.where(parent_id: App.cu.user_obj.id)
    end
    count = ds.count
    return_success(ds.offset(offset).limit(limit).all.map(&:as_pos), total_pages: (count / page_size.to_f).ceil )
  end


  def get
    result = item.as_json(only: [:full_name, :email, :role, :id, :active])
    result.merge!(allowed_properties: item.property_ids, properties: Property.all.map{|p| {name: p.name, id: p.id}} )
    return_success(result)
  end

  def create
    obj = model.new(data_for(:save))
    if App.cu.user_obj.role == 2
      obj.role = 3
    end
    save(obj)
  end

  def info
    return_success(
      App.cu.user_obj.as_json(only: [:email, :id, :full_name, :role, :updated_at])
    )
  end

  def update_password
    
    if App.cu.user_obj.password == params[:current_password]
      u = App.cu.user_obj
      u.password = params[:new_password]
      save(u) do |u|
        return_success("successfully updated password!!")
      end
    else
      return_errors!("Invalid password!!")
    end
  end

  def forgot_password
    email = params[:email]
    if email.present?
      user = App::Models::User.where(email: email).first
      if user
        user.send_password_reset_email('https://vhrr.net')
        return_success("Password reset email sent to #{user.email}")
      else
        return_errors("User not found with email: #{email}", 404)
      end
    else
      return_errors("User email is required!", 400)
    end
  end


  def validate_password_token
    token = params['token']
    
    if token.nil? || token.empty?
      return_errors!('Token is missing.', 400)
    else
      user = App::Models::User.where(reset_token: token).first
      if user && token_valid?(user)
        return_success('Token is valid.')
      else
        return_errors!('Invalid or expired token.')
      end
    end
  end

  def token_valid?(user)
    return false if user.reset_sent_at.nil?
  
    token_age = Time.now - user.reset_sent_at
    token_age < RESET_TOKEN_EXPIRATION_TIME
  end

  def reset_password
    token = params['token']
    new_password = params['password']

    if token.nil? || new_password.nil?
      return_errors!('Token and new password are required.', 400)
    else
      user = App::Models::User.where(reset_token: token).first
      if user && token_valid?(user)
        # Update the user's password and clear the reset token
        user.update(
          password: new_password,  # Use your password hashing logic here
          reset_token: nil,
          reset_sent_at: nil
        )
        return_success('Password has been reset.')
      else
        return_errors!('Invalid or expired token.', 400)
      end
    end
  end

  def load_rgms
    return_success(
      model.where(role: 2).all.map{|u| {id: u.id, name: u.full_name, property_ids: u.property_ids}}
    )
  end
  




  def self.fields
    {
      save: [:full_name, :password, :email, :role, :property_ids, :active]
    }
  end
end