require 'base64'

class App::Services::ProductImports < App::Services::Base
  # Admin: the client's filled-in product Excel. `check` says what would change (nothing is saved);
  # `run` imports it — all or nothing — with an audit entry for every change, one batch per import.
  MAX_BYTES = 5 * 1024 * 1024

  def check
    return_success(importer.preview)
  rescue ProductImport::Error => e
    return_errors!(e.message)
  end

  def run
    import = importer
    preview = import.preview
    return_errors!("The file has #{preview[:error_count]} problem(s) — check it and fix them first", 422) unless preview[:ok]

    return_success(import.apply!(batch_id: SecureRandom.hex(6)))
  rescue ProductImport::Error => e
    return_errors!(e.message)
  end

  private

  # data: { file: base64 of the .xlsx, hide_missing: true to hide website products that aren't in the file }
  def importer
    encoded = params && params[:file].to_s
    return_errors!('Choose the filled-in Excel file') if encoded.blank?
    bytes = Base64.decode64(encoded.sub(/\Adata:[^,]*,/, ''))
    return_errors!('The file is too big (5 MB at most)') if bytes.bytesize > MAX_BYTES

    ProductImport.new(bytes, hide_missing: [true, 'true'].include?(params[:hide_missing]))
  end
end
