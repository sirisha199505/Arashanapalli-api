class App::Models::AuditLog < Sequel::Model(:audit_logs)
  # one entry of the audit trail — written by Audit.log, never edited
end
