class App::Helpers::Before
  def self.run!(request)
    clear_thread_space!
    set_auth_token!(request.env['HTTP_AUTHORIZATION'])
    set_ip_address!(current_ip(request))
    set_did!(request.env['HTTP_X_DID'])
    
    # Log request information in development mode
    if App.development?
      App.logger.debug("Request: #{request.request_method} #{request.path}")
      App.logger.debug("IP: #{Thread.current[:app_space][:ip]}")
      App.logger.debug("DID: #{Thread.current[:app_space][:did]}")
    end
  end

  def self.current_ip(req)
    begin
      forwarded_ips = (req.env['HTTP_X_FORWARDED_FOR'] || '').split(',')
      connecting_ip = req.env['HTTP_DO_CONNECTING_IP'] || ''
      
      # Filter out the connecting IP if it's in the forwarded IPs
      filtered_ips = forwarded_ips - [connecting_ip].compact
      
      # Use the first forwarded IP, or fall back to the request's IP
      ip = filtered_ips.first&.strip || req.ip
      
      # Fix typo in log message
      App.logger.debug("Setting ip header: #{ip}") if App.development?
      
      return ip
    rescue => e
      App.logger.error("Error determining IP address: #{e.message}")
      return req.ip # Fallback to request IP on error
    end
  end

  def self.clear_thread_space!
    Thread.current[:app_space] = {}
  end

  def self.set_auth_token!(token)
    # Sanitize token before storing
    if token.present?
      # Remove any leading/trailing whitespace
      sanitized_token = token.strip
      Thread.current[:app_space][:auth_token] = sanitized_token
    else
      Thread.current[:app_space][:auth_token] = nil
    end
  end

  def self.set_did!(did)
    Thread.current[:app_space][:did] = did.present? ? did.strip : nil
  end

  def self.set_ip_address!(ip)
    Thread.current[:app_space][:ip] = ip
  end
end