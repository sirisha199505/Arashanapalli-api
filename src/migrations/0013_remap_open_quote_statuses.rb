Sequel.migration do
  # Quotations the previous version of the app saved as 'open' after migration 0011 had run (it kept running until
  # the new version was deployed): the same remap again. Run this once the new backend is live.
  up do
    run <<~SQL
      UPDATE quotes SET status = CASE WHEN contacted THEN 'contacted' ELSE 'sent' END WHERE status = 'open'
    SQL
  end

  down do
    # nothing to undo: 'open' no longer exists
  end
end
