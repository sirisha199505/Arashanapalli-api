Sequel.migration do
  up do
    # code: short shelf-sticker code (AT1001…) the sales team types to find a product
    # new_arrival: shown in the website's New Arrivals sections
    alter_table(:products) do
      add_column :code, String
      add_column :new_arrival, TrueClass, default: false
    end

    # number every existing product in catalog order
    run <<~SQL
      UPDATE products SET code = numbered.code
      FROM (SELECT id, 'AT' || (1000 + row_number() OVER (ORDER BY position, id)) AS code FROM products) numbered
      WHERE products.id = numbered.id
    SQL

    # starting New Arrivals: the last 4 products of each category (untick them in the admin as needed)
    run <<~SQL
      UPDATE products SET new_arrival = true
      WHERE id IN (
        SELECT id FROM (
          SELECT id, row_number() OVER (PARTITION BY category ORDER BY position DESC, id DESC) AS n FROM products WHERE active
        ) ranked WHERE n <= 4
      )
    SQL

    alter_table(:products) do
      add_index :code, unique: true
      add_index :new_arrival
    end
  end

  down do
    alter_table(:products) do
      drop_index :new_arrival
      drop_index :code
      drop_column :new_arrival
      drop_column :code
    end
  end
end
