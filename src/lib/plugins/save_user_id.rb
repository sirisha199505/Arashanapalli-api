module SequelPlugin
  module SaveUserId
    module InstanceMethods
      def before_create
        if respond_to?(:created_by=) && App::Helpers::CurrentUser.respond_to?(:id)
          self.created_by ||= App::Helpers::CurrentUser.id
        end
        
        if respond_to?(:created_ip=) && App::Helpers::CurrentUser.respond_to?(:ip)
          self.created_ip = App::Helpers::CurrentUser.ip
        end
        
        super
      end

      def before_save
        if respond_to?(:updated_by=) && App::Helpers::CurrentUser.respond_to?(:id)
          self.updated_by = App::Helpers::CurrentUser.id
        end
        
        if respond_to?(:updated_at=)
          self.updated_at = Time.now
        end
        
        if respond_to?(:updated_ip=) && App::Helpers::CurrentUser.respond_to?(:ip)
          self.updated_ip = App::Helpers::CurrentUser.ip
        end

        super
      end
    end
  end
end