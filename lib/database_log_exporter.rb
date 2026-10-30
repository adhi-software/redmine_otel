# frozen_string_literal: true

require 'json'
require_relative 'database_writer'

module RedmineObservability
  # Saves log records to ob_logs for the Logs tab of Administration > Redmine Observability.
  class DatabaseLogExporter
    include DatabaseWriter

    # Longer messages, like stack traces, are cut to this length.
    MAX_BODY_LENGTH = 16_000

    def export(log_records, timeout: nil)
      write(ObLog, log_records.map { row(_1) }, :logged_at, :logs) unless log_records.empty?
      OpenTelemetry::SDK::Logs::Export::SUCCESS
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: 'redmine_observability: could not save log records')
      OpenTelemetry::SDK::Logs::Export::FAILURE
    end

    def force_flush(timeout: nil) = OpenTelemetry::SDK::Logs::Export::SUCCESS

    def shutdown(timeout: nil) = OpenTelemetry::SDK::Logs::Export::SUCCESS

    private

    def row(record)
      attributes = record.attributes.to_h
      {
        logged_at: Time.at(Rational(record.timestamp || record.observed_timestamp, 1_000_000_000)),
        severity_number: record.severity_number.to_i,
        severity_text: record.severity_text.to_s.first(10).presence,
        # Read as UTF-8, so a binary message cannot fail the whole batch.
        body: record.body.to_s.dup.force_encoding(Encoding::UTF_8).scrub.truncate(MAX_BODY_LENGTH),
        trace_id: hex(record.trace_id, OpenTelemetry::Trace::INVALID_TRACE_ID),
        span_id: hex(record.span_id, OpenTelemetry::Trace::INVALID_SPAN_ID),
        details: ({ attributes: limit(attributes) }.to_json if attributes.any?)
      }
    end

    def hex(id, invalid) = (id.unpack1('H*') if id && id != invalid)
  end
end
