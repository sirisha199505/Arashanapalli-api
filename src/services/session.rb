class App::Services::Session < App::Services::Base

  def login
    user = User.find(email: params[:email]&.strip, active: true)

    unless user && user.password == params[:password]
      return_errors!("Invalid Email / Password")
    end

    # Device binding check
    if App.cu.current_did.present?
      user.device_uuid ||= App.cu.current_did
      if user.device_uuid != App.cu.current_did
        return_errors!("Not allowed to login from multiple devices. Please contact support.")
      end
    end

    user.last_logged_in_at = Time.now
    user.current_session_id = CurrentUser.encoded_token(user)

    if user.save
      return_success(token: user.current_session_id, info: user.as_pos)
    else
      return_errors!(user.errors, 400)
    end
  rescue => e
    App.logger.error("Login error: #{e.message}")
    App.logger.error(e.backtrace.join("\n"))
    return_errors!("An error occurred during login. Please try again.")
  end
end
