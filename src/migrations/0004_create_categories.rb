Sequel.migration do
  change do
    # Product categories: display order and icon for the website. Products refer to a category by name.
    create_table(:categories) do
      primary_key :id
      String :name, null: false, unique: true
      String :icon, default: 'box'
      Integer :position, default: 0
      TrueClass :active, default: true
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
