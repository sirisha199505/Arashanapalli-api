module App
  class<<self
    attr_reader :db, :audit_db
    NUMBER_OF_CONNECTIONS = ENV['POOL_SIZE'] || 1
    
    def development?
      env == 'development'
    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end

    def env
      @env ||= ENV['RACK_ENV'] || 'development'
    end

    def root
      @root ||= File.expand_path(File.dirname(__FILE__) + '/../')
    end

    def require_blob(blb)
      Dir[File.join(root, 'src', blb)].each {|f| require f}
    end

    def db_url
      ENV.fetch('DB_URL') { raise "DB_URL environment variable is required" }
    end

    def load!
      # First connect to the database
      connect_to_database
      
      # Load libraries before models
      require_blob('lib/**/*.rb')
      
      # Setup Sequel configuration
      setup_sequel!
      
      # Load helpers before models
      App.require_blob('helpers/*.rb')
      
      # Load models in the correct order
      require_blob('models/concerns/*.rb')
      require_blob('models/*.rb')
      require_blob('models/**/*.rb')
      
      # Load routes last
      require_relative 'routes'

      # Configure AWS with environment variables
      setup_aws_config
    end

    def connect_to_database
      @db = Sequel.connect(db_url, 
        max_connections: NUMBER_OF_CONNECTIONS, 
        logger: logger, 
        after_connect: Proc.new { logger.info("Database connection established") }
      )
      @db.extension(:connection_validator)
      @db.pool.connection_validation_timeout = 3600
    end
    
    def setup_aws_config
      # Use environment variables instead of hardcoded credentials
      aws_access_key = ENV['AWS_ACCESS_KEY_ID']
      aws_secret_key = ENV['AWS_SECRET_ACCESS_KEY']
      aws_region = ENV['AWS_REGION'] || 'ap-south-1'
      
      Aws.config.update(
        region: aws_region,
        credentials: Aws::Credentials.new(aws_access_key, aws_secret_key),
      )
      
      logger.info("AWS configuration initialized for region: #{aws_region}")
    end

    def cu
      App::Helpers::CurrentUser
    end

    def generate_id
      Time.now.utc.strftime("%Y%m%d%k%M%S%L%N").to_i.to_s(36)
    end

    def setup_sequel!
      Sequel::Model.plugin :validation_helpers
      Sequel::Model.plugin :force_encoding, 'UTF-8'
      Sequel::Model.plugin(::SequelPlugin::SaveUserId)
      # Sequel::Model.plugin(::SequelPlugin::JsonValuesValidations)
      # Sequel::Model.plugin(::SequelPlugin::JsonValueTypecast)
      Sequel::Model.plugin(::SequelPlugin::DefaultJson)
      Sequel::Model.plugin :nested_attributes
      Sequel::Model.plugin :dirty
      Sequel::Model.plugin :json_serializer
      Sequel::Model.raise_on_save_failure = false
      Sequel.extension :core_extensions
      Sequel.extension :named_timezones
      Sequel.extension :pg_json_ops
      Sequel.extension :pg_array_ops
      db.extension :pg_json, :pg_array, :pg_enum
      db.wrap_json_primitives = true
      db.typecast_json_strings = true
    end
  end

  module Models
  end
  module Services
  end
  module Helpers; end
  module Router; end
end