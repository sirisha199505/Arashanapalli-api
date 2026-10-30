module App::Helpers::Auth
  def self.included(klass)
    klass.class_eval do
      def auth_required!(*roles)
        unless App.cu.valid?
          r.halt(401, {'Content-Type' => 'application/json'}, {status: 'Unauthorized!'}.to_json)
        end

        if roles.length > 0 && !roles.include?(App.cu.role)
          r.halt(403, {'Content-Type' => 'application/json'}, {status: 'Forbidden!'}.to_json)
        end
      end
    end
  end
end