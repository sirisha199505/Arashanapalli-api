
class App::Routes < Roda
  include App::Router::AllPlugins
  plugin :not_found do
    { status: 'error', data: 'Not Found' }
  end

  # key: Integer for numeric ids, String for slug ids (products, brands)
  def do_crud(klass, r, only='CRUDL', opts = {}, key: Integer)
    r.post { klass[r, opts].create } if only.include?('C')
    r.get(key) {|id| klass[r, opts.merge(id: id)].get} if only.include?('R')
    r.get { klass[r, opts].list } if only.include?('L')
    r.put(key) {|id| klass[r, opts.merge(id: id)].update } if only.include?('U')
    r.delete(key) {|id| klass[r, opts.merge(id: id)].delete } if only.include?('D')
  end

  route do |r|
    r.public

    r.root do
      File.read(File.join(App.root, 'public', 'index.html'))
    end

    r.on 'admin' do
      r.get do
        File.read(File.join(App.root, 'public', 'index.html'))
      end
    end

    r.on 'api' do
      r.response['Content-Type'] = 'application/json'
      
      # Public endpoints (no auth required)
      r.post('login') { Session[r].login }
      r.post('forgot-password') { Users[r].forgot_password }
      r.post('validate-password-token') { Users[r].validate_password_token }
      r.post('reset-password') { Users[r].reset_password }
      
      r.get 'version' do
        { status: 'success', version: 1 }
      end

      # Website: catalog to render, and quote requests customers send
      r.get('catalog') { Catalog[r].show }
      r.post('quotes') { Quotes[r].submit }

      # Authentication required for all routes below
      auth_required!

      # User profile routes
      r.on 'me' do
        r.get('info') { Users[r].info }
        r.put('update-password') { Users[r].update_password }
      end

      # Admin-only routes
      admin_required!
      
      # Wrap all admin routes in error handling
      begin
        r.on 'users' do
          do_crud(Users, r, 'CRUDL')
        end

        r.on 'products' do
          r.delete(String) {|id| Products[r, id: id].remove } # soft delete: saved quotes still refer to it
          do_crud(Products, r, 'CRUL', key: String)
        end

        r.on 'brands' do
          r.delete(String) {|id| Brands[r, id: id].remove }
          do_crud(Brands, r, 'CRUL', key: String)
        end

        r.on 'quotes' do
          do_crud(Quotes, r, 'RLU')
        end

        r.on 'categories' do
          do_crud(Categories, r, 'CRUDL')
        end

        r.on 'series' do
          do_crud(Series, r, 'CRUDL')
        end

        r.get('dashboard') { Dashboard[r].show }

        r.on 'customers' do
          r.get { Customers[r].list }
        end

        # Add other admin routes here
      rescue => e
        App.logger.error("API Error: #{e.message}")
        App.logger.error(e.backtrace)
        { status: 'error', message: "An error occurred: #{e.message}" }
      end
    end

    # Fallback route
    r.get do
      File.read(File.join(App.root, 'public', 'index.html'))
    end
  end

  before do
    @time = Time.now
    App::Helpers::Before.run!(request)
  end

  after do |res|
    rtype = request.request_method
    App.logger.info("→ [#{Time.now - @time} seconds] - [#{rtype}]#{request.path}")
  end

  def auth_required!
    unless App.cu.valid?
      request.halt(401, {'Content-Type' => 'application/json'},{ status: 'Unauthorized!' }.to_json)
    end
  end

  def admin_required!
    unless (App.cu.user_obj.admin? || App.cu.user_obj.rgm?)
      request.halt(403, {'Content-Type' => 'application/json'},{ status: 'Forbidden!' }.to_json)
    end
  end
end

App.require_blob('services/base.rb')
App.require_blob('services/*.rb')

App::Routes.send(:include, App::Services)