Sequel.migration do
  # Quotation workflow: versions (AT-2611-7K3P9 → AT-2611-7K3P9-001), contacted flag, B2B details,
  # where the quote came from, validity, follow-up date and the salesperson it is assigned to.
  up do
    alter_table(:quotes) do
      add_column :base_number, String # the original quotation's ID, shared by all its versions
      add_column :version, Integer, default: 0 # 0 = the original, 1 = -001 …
      add_column :parent_id, Integer # the quotation this version was made from
      add_column :contacted, TrueClass, default: false
      add_column :contacted_at, DateTime
      add_column :customer_email, String
      add_column :customer_type, String, default: 'B2C'
      add_column :company_name, String
      add_column :gstin, String
      add_column :source, String, default: 'online' # online, walk_in, phone, whatsapp
      add_column :valid_until, Date
      add_column :follow_up_on, Date
      add_column :assigned_to, Integer # users.id of the salesperson
    end

    # statuses become open / accepted / lost; "contacted" is now its own flag
    run <<~SQL
      UPDATE quotes SET
        contacted = (status IN ('contacted', 'won', 'lost')),
        status = CASE status WHEN 'won' THEN 'accepted' WHEN 'lost' THEN 'lost' ELSE 'open' END,
        base_number = quote_number,
        valid_until = (created_at::date + 15)
    SQL
    alter_table(:quotes) do
      set_column_default :status, 'open'
      add_index :quote_number, unique: true
      add_index :base_number
      add_index :customer_phone
      add_index :contacted
      add_index :follow_up_on
      add_index :valid_until
    end
  end

  down do
    alter_table(:quotes) do
      drop_index :valid_until
      drop_index :follow_up_on
      drop_index :contacted
      drop_index :customer_phone
      drop_index :base_number
      drop_index :quote_number
      %i[base_number version parent_id contacted contacted_at customer_email customer_type company_name gstin source valid_until follow_up_on assigned_to].each { |c| drop_column c }
      set_column_default :status, 'new'
    end
  end
end
