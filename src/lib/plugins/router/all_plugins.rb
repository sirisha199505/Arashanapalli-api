module App::Router::AllPlugins
  def self.included(klass)
    klass.plugin :all_verbs
    klass.plugin :hooks
    klass.plugin :halt
    klass.plugin :json
    klass.plugin :json_parser
    klass.plugin :indifferent_params
    klass.plugin :public
  end
end