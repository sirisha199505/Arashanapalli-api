
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

      r.get 'version' do
        { status: 'success', version: 1 }
      end

      # Website: catalog to render, and quote requests customers send
      r.get('catalog') { Catalog[r].show }
      r.post('quotes') { Quotes[r].submit }
      r.get('quotes/track', String) { |number| Quotes[r, number: number].track }
      r.get('quotes/pdf', String) { |number| Quotes[r, number: number].pdf }
      r.get('quotes/upi-qr', String) { |number| Quotes[r, number: number].upi_qr }
      r.get('quotes/compare.pdf') { Quotes[r].compare_pdf }
      r.get('quotes/compare') { Quotes[r].compare }

      # Customers: sign in with a code sent to their email, then see their quotations
      r.post('customer/code') { CustomerAccount[r].request_code }
      r.post('customer/verify') { CustomerAccount[r].verify }
      r.get('customer/quotes') { CustomerAccount[r].quotes }

      # Authentication required for all routes below
      auth_required!
      # any staff change may touch products, brands, prices or categories: the website's cached catalog is rebuilt
      App::Services::Catalog.expire! unless r.get?

      # The signed-in staff member
      r.on 'me' do
        r.get('info') { Users[r].info }
        r.put('update-password') { Users[r].update_password }
      end

      # Any staff (Admin, Sales, Limited sales — what each sees is limited inside the services)
      staff_required!

      begin
        r.on 'quotes' do
          r.post('staff') { Quotes[r].create } # walk-in / phone quotations made by the sales team
          r.post(Integer, 'revise') { |id| Quotes[r, id: id].revise } # new version: AT-…-001
          r.post(Integer, 'activities') { |id| Quotes[r, id: id].log_activity } # follow-up actions
          r.post(Integer, 'order') { |id| Quotes[r, id: id].convert } # accepted → order
          do_crud(Quotes, r, 'RLU')
        end

        r.get('dashboard') { Dashboard[r].show }
        r.get('staff') { Users[r].staff }

        r.on 'customers' do
          r.get { Customers[r].list }
        end

        r.on 'orders' do
          do_crud(Orders, r, 'RLU')
        end

        r.on 'templates' do
          do_crud(Templates, r, 'CRUDL')
        end

        # Admin only: staff accounts and the catalog
        admin_required!

        r.get('audit') { AuditLogs[r].list }

        r.on 'users' do
          do_crud(Users, r, 'CRUL')
        end

        r.on 'products' do
          # the client's product Excel: check it (nothing saved), then import it
          r.post('import', 'check') { ProductImports[r].check }
          r.post('import') { ProductImports[r].run }
          # bulk updates, a page of products at a time (before the CRUD routes, which would read 'bulk' as an id)
          r.is 'bulk' do
            r.get { ProductBulk[r].list }
            r.put { ProductBulk[r].update }
          end
          r.delete(String) {|id| Products[r, id: id].remove } # soft delete: saved quotes still refer to it
          do_crud(Products, r, 'CRUL', key: String)
        end

        r.on 'brands' do
          r.delete(String) {|id| Brands[r, id: id].remove }
          do_crud(Brands, r, 'CRUL', key: String)
        end

        r.on 'categories' do
          do_crud(Categories, r, 'CRUDL')
        end

        r.on 'series' do
          do_crud(Series, r, 'CRUDL')
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

  def staff_required!
    unless App.cu.user_obj&.staff?
      request.halt(403, {'Content-Type' => 'application/json'},{ status: 'error', data: 'Not allowed' }.to_json)
    end
  end

  def admin_required!
    unless App.cu.user_obj&.admin?
      request.halt(403, {'Content-Type' => 'application/json'},{ status: 'error', data: 'Only an admin can do that' }.to_json)
    end
  end
end

App.require_blob('services/base.rb')
App.require_blob('services/*.rb')

App::Routes.send(:include, App::Services)