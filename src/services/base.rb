
class App::Services::Base
  attr_reader :request

  include App::Models
  include App::Helpers

  def initialize(r)
    @request = r
  end

  def self.[](r, hash={})
    r.params.merge!(hash)
    new(r)
  end

  def json(r)
    r.to_json
  end

  def current_user
    @current_user ||= App::Helpers::CurrentUser.decoded_token
  end

  # Consider standardizing error response format
  def return_errors!(errors, code=400)
    request.halt(code, { status: 'error', data: errors })
  end

  # Consider adding validation for allowed fields
  def data_for(fn)
    allowed = a_flds[fn]
    return {} unless allowed # Add protection against missing field definitions
    
    keys = allowed[:flds].keys || []
    data = params.slice(*keys)
    allowed[:sub_flds].each do |key|
      next unless data[key].is_a?(Array) # Add protection against nil or non-array values
      data[key] = data[key].map {|d| d.slice(*allowed[:flds][key])}
    end

    data
  end

  def authorize!(*roles)
    # This method doesn't actually check anything - consider implementing real authorization
    true
  end

  def return_success(data, extras={})
    { status: 'success', data: data }.merge!(extras)
  end

  def return_success!(data, extras={})
    request.halt(200, { status: 'success', data: data }.merge!(extras))
  end

  # Good error handling here, but consider adding transaction support
  def save(obj, &block)
    if obj.save
      block_given? ? yield(obj) : return_success(obj.to_pos)
    else
      return_errors!(obj.errors, 400)
    end
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!(e.message, 400)
  end

  def check_presence!(*flds)
    empty = flds.select do |f|
      params&.dig(*f).blank?
    end

    if empty.present?
      errors = empty.reduce({}) do |h, f|
        key = f.is_a?(Array) ? f.join('.') : f
        h.merge!(key => "Can't be blank")
      end
      return_errors!(errors, 400)
    end
  end

  def params
    @params ||=qs[:data]
  end

  def qs
    @qs ||= r.params.with_indifferent_access
  end

  def r; request; end
  def rp; request.params; end


  # Basic Operations

  def list
    return_success(model.order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  def get
    return_success(item.to_pos)
  end

  def create
    obj = model.new(data_for(:save))
    save(obj)
  end

  def update(data=nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item)
  end

  def delete
    res = item.delete
    res ? return_success(res.to_pos) : return_errors!('Unable to delete')
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!(e.message, 400)
  end

  def remove
    item.active = false
    save(item)
  end

  def item(id=rp[:id])
    @item ||= begin
      model[id] || return_errors!("No #{model.class} found with id: #{id}", 404)
    end
  end

  def add_obj
    name = r.params[:name]
    obj_id = r.params[:obj_id]
    fld = "#{name}_ids"

    obj_val = item.send(fld)

    if(obj_val)
      obj_val << obj_id
      obj_val.uniq!
    else
      item.send("#{fld}=", [obj_id])
    end
    save(item)
  end

  def remove_obj
    name = r.params[:name]
    obj_id = r.params[:obj_id]
    fld = "#{name}_ids"
    obj_val = item.send(fld)
    if(obj_val)
      item.send(fld).delete(obj_id)
    end
    save(item)
  end

  def offset
    ((qs[:page] || 1).to_i - 1) * page_size
  end

  def limit
    page_size
  end

  def page_size
    [(qs[:page_size] || 20).to_i, 300].min
  end

  def current_client_id
    App.cu.user_obj.client_id
  end

  def to_est(time)
    # "Eastern Time (US & Canada)" is the Rails time zone name for EST/EDT.
    time.in_time_zone("Eastern Time (US & Canada)")
  end

  def format_currency(amount)
    return '$0.00' if amount.nil?

    # Convert from cents to dollars
    value = amount.to_f / 100
    # Format the value to 2 decimal places
    formatted = sprintf('%.2f', value)
    integer_part, fractional_part = formatted.split('.')
    # Insert commas for thousands separators
    integer_with_commas = integer_part.reverse.scan(/\d{1,3}/).join(',').reverse
    "$#{integer_with_commas}.#{fractional_part}"
  end

  private

  def a_flds; self.class.allowed_fields; end

  def self.allowed_fields
    @allowed_fields ||= begin
      fields.with_indifferent_access.reduce({}) do |h, (action, data)|
        puts "action: #{action}"
        h.merge!(action => build_allowed_fields(data))
      end
    end.with_indifferent_access
  end

  def self.build_allowed_fields(schema, res={flds: {},  sub_flds: []})
    schema.each do |e|
      if e.is_a?(String) || e.is_a?(Symbol)
        res[:flds][e] = {}
      elsif e.is_a?(Hash)
        key, value = e.keys[0], e.values[0]
        if value.is_a?(Array)
          build_allowed_fields(value, res)
          res[:sub_flds] << key
        elsif value.is_a?(Hash)
          res[:flds].merge!(e)
        end
      end
    end
    res
  end
end