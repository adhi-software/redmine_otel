# frozen_string_literal: true

module RedmineObservability
  # Saves an exporter's rows from its own thread, and hourly deletes rows older than the retention
  # days of its signal: traces, logs or metrics.
  module DatabaseWriter
    # Longer strings, like SQL or stack traces, are cut to this length.
    MAX_VALUE_LENGTH = 4_000
    CLEANUP_INTERVAL = 3600

    private

    # Untraced, or saving the rows would record new SQL spans, log lines and metrics;
    # wrapped like a request, since an exporter runs outside one.
    def write(model, rows, time_column, signal)
      OpenTelemetry::Common::Utilities.untraced do
        Rails.application.reloader.wrap do
          model.insert_all(rows, returning: false)
          delete_expired(model, time_column, signal)
        end
      end
    end

    # Each process runs this; deleting already deleted rows is harmless.
    def delete_expired(model, time_column, signal)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if now < (@next_cleanup ||= 0)

      @next_cleanup = now + CLEANUP_INTERVAL
      model.where(time_column => ...RedmineObservability.retention_days(signal).days.ago)
           .in_batches(of: 10_000).delete_all
    end

    def limit(attributes)
      attributes.transform_values { _1.is_a?(String) ? _1.truncate(MAX_VALUE_LENGTH) : _1 }
    end
  end
end
