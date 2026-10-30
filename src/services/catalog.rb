class App::Services::Catalog < App::Services::Base
  # Public: everything the website needs to render products, brands and prices
  def show
    return_success(
      brands: Brand.where(active: true).order(:position, :name).all.map(&:as_catalog),
      products: Product.where(active: true).order(:position, :name).all.map(&:as_catalog)
    )
  end
end
