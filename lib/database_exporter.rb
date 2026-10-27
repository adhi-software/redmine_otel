require 'json'

module RedmineObservability
  # Saves spans to ob_spans for Administration > Traces, and deletes expired ones hourly.
  class DatabaseExporter
    # Longer strings, like SQL or stack traces, are cut to this length.
    MAX_VALUE_LENGTH = 4_000
    CLEANUP_INTERVAL = 3600

    def initialize
      @next_cleanup = 0
    end

    # Runs on the batch processor's thread, so it wraps the work like a request.
    def export(span_data, timeout: nil)
      return OpenTelemetry::SDK::Trace::Export::SUCCESS if span_data.empty?

      rows = span_data.map { row(_1) }
      # Untraced, or saving the spans would record new SQL spans.
      OpenTelemetry::Common::Utilities.untraced do
        Rails.application.reloader.wrap do
          ObSpan.insert_all(rows, returning: false)
          delete_expired
        end
      end
      OpenTelemetry::SDK::Trace::Export::SUCCESS
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: 'redmine_observability: could not save spans')
      OpenTelemetry::SDK::Trace::Export::FAILURE
    end

    def force_flush(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS

    def shutdown(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS

    private

    def row(span)
      attributes = span.attributes.to_h
      has_parent = span.parent_span_id != OpenTelemetry::Trace::INVALID_SPAN_ID
      status = (attributes['http.response.status_code'] || attributes['http.status_code'])&.to_i
      details = { attributes: limit(attributes), events: events(span), status: span.status.description.presence }
      {
        trace_id: span.hex_trace_id,
        span_id: span.hex_span_id,
        parent_span_id: (span.hex_parent_span_id if has_parent),
        # A remote parent, such as the mobile app's span, is not stored here.
        root: !has_parent || span.parent_span_is_remote == true,
        kind: span.kind.to_s,
        name: span.name.to_s.truncate(255),
        target: target(attributes)&.truncate(255),
        http_status: status&.positive? ? status : nil,
        error: span.status.code == OpenTelemetry::Trace::Status::ERROR,
        started_at: Time.at(Rational(span.start_timestamp, 1_000_000_000)),
        duration_us: (span.end_timestamp - span.start_timestamp) / 1000,
        details: details.compact.to_json
      }
    end

    def target(attributes)
      path = attributes['url.path']
      return attributes['http.target'] || attributes['url.full'] || attributes['http.url'] unless path

      query = attributes['url.query']
      query.present? ? "#{path}?#{query}" : path
    end

    def events(span)
      Array(span.events).map do |event|
        { name: event.name, offset_us: (event.timestamp - span.start_timestamp) / 1000,
          attributes: limit(event.attributes.to_h) }
      end.presence
    end

    def limit(attributes)
      attributes.transform_values { _1.is_a?(String) ? _1.truncate(MAX_VALUE_LENGTH) : _1 }
    end

    # Each process runs this; deleting already deleted rows is harmless.
    def delete_expired
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if now < @next_cleanup

      @next_cleanup = now + CLEANUP_INTERVAL
      ObSpan.where(started_at: ...RedmineObservability.retention_days.days.ago)
                       .in_batches(of: 10_000).delete_all
    end
  end
end
