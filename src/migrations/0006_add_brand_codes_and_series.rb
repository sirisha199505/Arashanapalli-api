Sequel.migration do
  up do
    # Brand code: the suffix of a product's dynamic code — AT1002 in Hettich is AT1002-HET
    alter_table(:brands) { add_column :code, String }
    {
      'godrej' => 'GOD', 'hettich' => 'HET', 'dorset' => 'DOR', 'ebco' => 'EBC', 'local' => 'ARA', 'greenply' => 'GRP',
      'century' => 'CEN', 'kitply' => 'KIT', 'archidply' => 'ARC', 'actiontesa' => 'ACT', 'merino' => 'MER', 'greenlam' => 'GRL',
      'royaletouche' => 'ROY', 'hafele' => 'HAF', 'blum' => 'BLU', 'ozone' => 'OZO', 'europa' => 'EUR', 'yale' => 'YAL',
      'pidilite' => 'FEV', 'asianpaints' => 'ASP', 'wipro' => 'WIP', 'philips' => 'PHI', 'rehau' => 'REH'
    }.each { |id, code| from(:brands).where(id: id).update(code: code) }
    # any other brand: first letters of its id, made unique with its position
    from(:brands).where(code: nil).each do |b|
      from(:brands).where(id: b[:id]).update(code: "#{b[:id].upcase.gsub(/[^A-Z]/, '')[0, 3]}#{b[:position]}")
    end
    alter_table(:brands) { add_index :code, unique: true }

    # Series: the "individual" level under a brand (class = tier, sub-class = brand), e.g. Hettich → InnoTech
    create_table(:brand_series) do
      primary_key :id
      String :brand_id, null: false
      String :name, null: false
      String :description, text: true
      Integer :position, default: 0
      TrueClass :active, default: true
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      foreign_key [:brand_id], :brands, key: :id, on_delete: :cascade
      index :brand_id
      unique [:brand_id, :name]
    end

    # which series a product belongs to (at most one per brand that makes it)
    alter_table(:products) { add_column :series_ids, 'integer[]', default: Sequel.lit("'{}'") }
  end

  down do
    alter_table(:products) { drop_column :series_ids }
    drop_table(:brand_series)
    alter_table(:brands) do
      drop_index :code
      drop_column :code
    end
  end
end
