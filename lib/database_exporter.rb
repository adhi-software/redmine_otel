# frozen_string_literal: true

require 'json'
require_relative 'database_writer'

module RedmineObservability
  # Saves spans to ob_spans for the Traces tab of Administration > Redmine Observability.
  class DatabaseExporter
    include DatabaseWriter

    def export(span_data, timeout: nil)
      return OpenTelemetry::SDK::Trace::Export::SUCCESS if span_data.empty?

      write(ObSpan, span_data.map { row(_1) }, :started_at, :traces)
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
  end
end
