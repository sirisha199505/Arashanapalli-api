# Puma config — used locally and in Docker/Render.
# Render (and most hosts) tell the app which port to use via $PORT; locally it's 9393
# (not Puma's usual 9292, which another project on this machine uses).
port ENV.fetch('PORT', 9393)

threads_count = Integer(ENV.fetch('RAILS_MAX_THREADS', ENV.fetch('POOL_SIZE', 5)))
threads threads_count, threads_count

# WEB_CONCURRENCY > 0 runs several worker processes (cluster mode); 0 keeps a single process
workers Integer(ENV.fetch('WEB_CONCURRENCY', 0))

# config.ru connects to the database while booting; each forked worker needs its own connections
before_worker_boot do
  App.db.disconnect if defined?(App) && App.db
end
