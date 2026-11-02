Sequel.migration do
  change do
    # Follow-up history of a quotation (all its versions share base_number): calls, WhatsApp messages, visits, notes …
    create_table(:quote_activities) do
      primary_key :id
      String :base_number, null: false
      Integer :quote_id # the version it was logged on
      String :kind, null: false # call, whatsapp, visit, email, note, version, status
      String :note, text: true
      Date :next_follow_up_on
      Integer :user_id
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :base_number
    end

    # Saved packages / template quotes, e.g. "Modular kitchen hardware set": products with quantities and an optional brand
    create_table(:quote_templates) do
      primary_key :id
      String :name, null: false
      String :description, text: true
      jsonb :items, default: Sequel.lit("'[]'::jsonb") # [{ product_id, quantity, brand_id? }]
      TrueClass :public, default: true # shown to customers on the website
      TrueClass :active, default: true
      Integer :position, default: 0
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
