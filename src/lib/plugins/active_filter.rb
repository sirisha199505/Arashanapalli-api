module Plugins
  module ActiveFilter
    def self.apply(model)
      # Automatically extend dataset_module in the model
      model.dataset_module do
        def active
          where(active: true)
        end
      end
    end
  end
end

# Register the plugin with Sequel
# Sequel::Model.plugin(:active_filter, Plugins::ActiveFilter)
