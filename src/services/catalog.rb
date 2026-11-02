class App::Services::Catalog < App::Services::Base
  # Public: everything the website needs to render products, brands and prices.
  # Hidden brands are left off every product, and products in a hidden category or with no visible brand are left out,
  # so the website never sees a reference it can't resolve.
  def show
    brands = Brand.where(active: true).order(:position, :name).all
    series = BrandSeries.where(active: true).order(:position, :name).all.group_by(&:brand_id)
    brand_ids = brands.map(&:id)
    hidden_categories = Category.where(active: false).select(:name)

    # each brand's own price / stock / photo / description, where one is set: { product_id => { brand_id => {...} } }
    details = ProductBrand.where(brand_id: brand_ids).all.group_by(&:product_id)
    products = Product.where(active: true).exclude(category: hidden_categories).order(:position, :name).all.filter_map do |p|
      shown = p.as_catalog.merge(brandIds: p.brand_ids.to_a & brand_ids)
      offers = details[p.id].to_a.filter_map { |d| [d.brand_id, d.as_catalog] if shown[:brandIds].include?(d.brand_id) }.to_h
      shown[:brandDetails] = offers if offers.any?
      shown if shown[:brandIds].any?
    end

    on_sale = Product.where(active: true).exclude(category: hidden_categories).to_hash(:id)
    packages = QuoteTemplate.where(active: true, public: true).order(:position, :name).all
                            .map { |t| t.as_catalog(on_sale, brand_ids) }.select { |t| t[:items].any? }

    return_success(
      packages: packages,
      categories: Category.where(active: true).order(:position, :name).all.map(&:as_catalog),
      brands: brands.map { |b| b.as_catalog(series[b.id] || []) },
      products: products
    )
  end
end
