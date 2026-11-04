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
    user.current_session_id = reusable_token(user) || CurrentUser.encoded_token(user)

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

  private

  # An account has one session. Signing in again (another device, browser or tab) shares it while it has more than a
  # day left, instead of replacing it — replacing it signed the other device out at once.
  # Resetting the password or deactivating the account still ends it (see Users#update).
  def reusable_token(user)
    token = user.current_session_id
    return nil if token.blank?
    payload = JWT.decode(token, CurrentUser::SECRET, true, { algorithm: 'HS256' })[0]
    token if payload['exp'].to_i > Time.now.to_i + 24 * 3600
  rescue JWT::DecodeError
    nil
  end
end
