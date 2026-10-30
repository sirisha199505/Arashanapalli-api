Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id

      String :full_name
      String :email, size: 100
      String :encoded_password, size: 200

      Integer :client_id

      Integer :role

      Integer :parent_id

      String :device_uuid
      String :phone_number
      jsonb :phone_numbers, default: '{}'

      column :logged_in_ips, 'text[]', default: '{}'
      column :property_ids, 'Integer[]', default: '{}'

      jsonb :tokens, default: '{}'

      jsonb :authorization, default: '{}'

      jsonb :extras, default: '{}'

      String :current_session_id, text: true


      DateTime :last_logged_in_at
      TrueClass :active, :default => true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end