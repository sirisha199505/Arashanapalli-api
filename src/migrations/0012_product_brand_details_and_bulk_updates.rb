Sequel.migration do
  up do
    # What a brand's version of a product has of its own (e.g. Godrej's Door Hinges): its price, stock, photo and
    # description. A product without a row here — or a blank column — uses the standard: base price × brand factor,
    # the product's photo and description.
    create_table(:product_brands) do
      foreign_key :product_id, :products, type: String, null: false, on_delete: :cascade
      foreign_key :brand_id, :brands, type: String, null: false, on_delete: :cascade
      primary_key [:product_id, :brand_id]
      Integer :price # blank = base price × brand factor
      String :stock_status # in_stock, low_stock, out_of_stock, on_order; blank = not tracked
      Integer :stock_qty
      String :image, text: true
      String :description, text: true
      Integer :updated_by
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :brand_id
    end

    # one bulk save = one batch: its audit entries can be looked at together
    alter_table(:audit_logs) do
      add_column :batch_id, String
      add_index :batch_id
    end
  end

  down do
    alter_table(:audit_logs) { drop_column :batch_id }
    drop_table(:product_brands)
  end
end
