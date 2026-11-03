Sequel.migration do
  # What the product Excel template collects beyond what products already had
  up do
    alter_table(:products) do
      add_column :sku, String # the shop's own item code — also how a re-import finds the product
      add_column :specification, String # size / specification, e.g. "8 ft x 4 ft, 18 mm"
      add_column :hsn_code, String
      add_column :gst_rate, Integer # %; quotations still use 18% for every product until per-product GST is switched on
      add_index :sku
    end
  end

  down do
    alter_table(:products) do
      drop_column :sku
      drop_column :specification
      drop_column :hsn_code
      drop_column :gst_rate
    end
  end
end
