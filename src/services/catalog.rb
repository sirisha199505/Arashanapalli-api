class App::Services::Catalog < App::Services::Base
  # Public: everything the website needs to render products, brands and prices.
  # Hidden brands are left off every product, and products in a hidden category or with no visible brand are left out,
  # so the website never sees a reference it can't resolve.
  def show
    brands = Brand.where(active: true).order(:position, :name).all
    series = BrandSeries.where(active: true).order(:position, :name).all.group_by(&:brand_id)
    brand_ids = brands.map(&:id)
    hidden_categories = Category.where(active: false).select(:name)

    products = Product.where(active: true).exclude(category: hidden_categories).order(:position, :name).all.filter_map do |p|
      shown = p.as_catalog.merge(brandIds: p.brand_ids.to_a & brand_ids)
      shown if shown[:brandIds].any?
    end

    return_success(
      categories: Category.where(active: true).order(:position, :name).all.map(&:as_catalog),
      brands: brands.map { |b| b.as_catalog(series[b.id] || []) },
      products: products
    )
  end
end
