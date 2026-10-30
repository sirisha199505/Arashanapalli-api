module SequelPlugin
  module DefaultJson
    module InstanceMethods
      def to_pos
        as_json.except("created_ip", "updated_ip")
      end
    end
  end
end