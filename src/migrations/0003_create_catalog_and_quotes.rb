Sequel.migration do
  change do
    # ids are slugs (e.g. 'hettich', 'door-hinges') so they match the ids the frontend already stores in saved quotes
    create_table(:brands) do
      String :id, primary_key: true
      String :name, null: false
      String :tier
      BigDecimal :price_factor, size: [5, 2], null: false, default: 1
      jsonb :specs, default: '{}'
      Integer :position, default: 0
      TrueClass :active, default: true
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:products) do
      String :id, primary_key: true
      String :name, null: false
      String :category, null: false
      String :image, text: true
      String :description, text: true
      String :unit, null: false, default: 'piece'
      Integer :base_price, null: false
      column :brand_ids, 'text[]', default: '{}'
      TrueClass :mock, default: false
      Integer :position, default: 0
      TrueClass :active, default: true
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :category
      index :active
    end

    # Quote requests customers send from the website (a snapshot — prices are kept as they were quoted)
    create_table(:quotes) do
      primary_key :id
      String :quote_number
      String :customer_name, null: false
      String :customer_phone, null: false
      String :customer_city
      String :sent_via
      jsonb :items, default: '[]'
      Integer :subtotal
      Integer :gst
      Integer :total
      String :status, default: 'new'
      String :notes, text: true
      String :created_ip
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :created_at
    end
  end
end
