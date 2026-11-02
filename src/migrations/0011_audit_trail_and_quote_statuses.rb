Sequel.migration do
  up do
    # Audit trail: every change that matters — who, when, what changed from → to
    create_table(:audit_logs) do
      primary_key :id
      String :entity_type, null: false # quote, order, product, brand, user
      String :entity_id, null: false
      String :ref # what it belongs to, e.g. a quotation's base ID (all its versions) or a product code
      String :action, null: false # created, updated, new_version, sent, accepted, …
      jsonb :changes, default: Sequel.lit("'{}'::jsonb") # { field: [from, to] } or { lines: [...] }
      String :note, text: true
      Integer :user_id
      String :user_name # as it was at the time
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index [:entity_type, :entity_id]
      index :ref
      index :created_at
    end

    # Quotation statuses: draft → sent → contacted → accepted / lost (expired is worked out from the validity date)
    run <<~SQL
      UPDATE quotes SET status = CASE
        WHEN status = 'open' AND contacted THEN 'contacted'
        WHEN status = 'open' THEN 'sent'
        ELSE status END
    SQL
    alter_table(:quotes) { set_column_default :status, 'draft' }
  end

  down do
    run "UPDATE quotes SET status = 'open' WHERE status IN ('draft', 'sent', 'contacted')"
    alter_table(:quotes) { set_column_default :status, 'open' }
    drop_table(:audit_logs)
  end
end
