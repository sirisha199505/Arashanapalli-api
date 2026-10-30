class App::Helpers::CurrentUser
  SECRET = ENV.fetch('JWT_SECRET') { raise "JWT_SECRET environment variable is required" }
  TOKEN_EXPIRY = 180.hours # Extracted as a constant for easier management

  class<<self
    def id
      decoded_token&.[](:id)
    end

    def role
      decoded_token&.[](:role)
    end

    def valid?
      return false if id.blank? || user_obj.nil?
      
      # Check if token matches and is not expired
      user_obj.current_session_id == token
    end

    def ip
      space[:ip]
    end

    def space
      Thread.current[:app_space] || {}
    end

    def current_did
      space[:did]
    end

    def token
      return nil if space[:auth_token].blank?
      
      space[:auth_token].gsub("Bearer ", "")
    end

    def decoded_token
      return nil if token.nil?

      space[:decoded] ||= begin
        decoded = JWT.decode(token, SECRET, true, { algorithm: 'HS256' })[0].with_indifferent_access
        
        # Check token expiration
        if decoded[:exp] && Time.now.to_i > decoded[:exp]
          App.logger.warn("Token expired for user #{decoded[:id]}")
          return nil
        end
        
        decoded
      rescue JWT::DecodeError => e
        App.logger.error("JWT decode error: #{e.message}")
        nil
      rescue => e
        App.logger.error("Token decode error: #{e.message}")
        nil
      end
    end

    def user_obj
      return nil if id.blank?
      
      space[:user_obj] ||= begin
        user = App::Models::User.where(active: true)[id]
        App.logger.warn("User not found or inactive: #{id}") if user.nil?
        user
      rescue => e
        App.logger.error("Error fetching user: #{e.message}")
        nil
      end
    end

    def basic_info
      return {} if user_obj.nil?
      
      user_obj.values.slice(:email, :first_name, :last_name, :role)
    end

    def admin?
      user_obj&.role === 0
    end

    def entity_ids
      user_obj&.entity_ids || []
    end

    def encoded_token(user)
      exp = (Time.now + TOKEN_EXPIRY).to_i
      payload = { 
        id: user.id, 
        role: user.role, 
        ip: ip, 
        exp: exp,
        iat: Time.now.to_i # Added issued at timestamp
      }
      JWT.encode(payload, SECRET, 'HS256')
    end
    
    def clear_cache!
      space.delete(:decoded)
      space.delete(:user_obj)
      @token = nil
    end
  end

  # Removed commented code
end