Sequel.migration do
  change do
    # One-time sign-in codes emailed to customers ("My quotations"): only a hash of the code is kept
    create_table(:customer_logins) do
      primary_key :id
      String :email, null: false
      String :code_digest, null: false
      DateTime :expires_at, null: false
      Integer :attempts, default: 0
      TrueClass :used, default: false
      String :created_ip
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :email
    end

    # An accepted quotation becomes an order (fulfilled offline for now): a copy of what was quoted, plus delivery and payment
    create_table(:orders) do
      primary_key :id
      String :order_number, null: false, unique: true # AO-2611-7K3P9
      Integer :quote_id, null: false
      String :quote_number, null: false
      String :base_number, null: false, unique: true # one order per quotation
      String :customer_name, null: false
      String :customer_phone, null: false
      String :customer_email
      String :customer_city
      String :customer_type, default: 'B2C'
      String :company_name
      String :gstin
      jsonb :items, default: Sequel.lit("'[]'::jsonb")
      Integer :subtotal
      Integer :gst
      Integer :total
      String :status, default: 'confirmed' # confirmed, processing, ready, delivered, cancelled
      String :payment_status, default: 'unpaid' # unpaid, partial, paid
      Integer :amount_paid, default: 0
      Date :delivery_on
      String :notes, text: true
      Integer :assigned_to
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :customer_phone
      index :created_at
    end
  end
end
