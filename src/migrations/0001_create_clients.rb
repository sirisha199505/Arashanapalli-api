Sequel.migration do
  change do
    create_table(:clients) do
      primary_key :id
      String :name, null: false
      String :email, unique: true
      column :assets, :jsonb, default: '[]'
      Boolean :active, default: true
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :email, unique: true
      index :active
    end
  end
end
