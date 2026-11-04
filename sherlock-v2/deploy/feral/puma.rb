# Dedicated Puma configuration for Feral's rootless deployment.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3).to_i
threads threads_count, threads_count

bind "tcp://#{ENV.fetch("BINDING", "127.0.0.1")}:#{ENV.fetch("PORT", "18443")}"

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
plugin :tmp_restart
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
