Sequel.migration do
  # subcategory: optional second level under a category (Plywood → BWR Plywood), shown as the website's category tree
  up do
    alter_table(:products) do
      add_column :subcategory, String
      add_index %i[category subcategory]
    end
    # the sample products are named "<type> – <variant>": their type becomes the subcategory
    run "UPDATE products SET subcategory = split_part(name, ' – ', 1) WHERE mock AND name LIKE '% – %'"
  end

  down do
    alter_table(:products) do
      drop_index %i[category subcategory]
      drop_column :subcategory
    end
  end
end
