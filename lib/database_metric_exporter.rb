# frozen_string_literal: true

require 'json'
require_relative 'database_writer'

module RedmineOpentelemetry
  # Saves metric points to ot_metrics for the Metrics tab.
  class DatabaseMetricExporter
    include DatabaseWriter

    MAX_SERIES_LENGTH = 1024
    NANOSECONDS_PER_MINUTE = 60_000_000_000

    def export(metrics, timeout: nil)
      rows = metrics.flat_map { |metric| metric.data_points.filter_map { row(metric, _1) } }
      write(OtMetric, rows, :recorded_at, :metrics) unless rows.empty?
      OpenTelemetry::SDK::Metrics::Export::SUCCESS
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: 'redmine_opentelemetry: could not save metrics')
      OpenTelemetry::SDK::Metrics::Export::FAILURE
    end

    def force_flush(timeout: nil) = OpenTelemetry::SDK::Metrics::Export::SUCCESS

    def shutdown(timeout: nil) = OpenTelemetry::SDK::Metrics::Export::SUCCESS

    private

    def row(metric, point)
      histogram = point.is_a?(OpenTelemetry::SDK::Metrics::Aggregation::HistogramDataPoint)
      return if histogram && point.count.zero?

      details = { description: metric.description.presence }
      details.update(bounds: point.explicit_bounds, counts: point.bucket_counts) if histogram
      {
        name: metric.name.to_s.truncate(255),
        kind: metric.instrument_kind.to_s,
        unit: metric.unit.to_s.first(30).presence,
        series: point.attributes.to_h.sort.to_h.to_json.truncate(MAX_SERIES_LENGTH),
        recorded_at: Time.at(Rational(point.time_unix_nano, 1_000_000_000)),
        minute: point.time_unix_nano / NANOSECONDS_PER_MINUTE,
        value: histogram ? point.sum : point.value,
        count: (point.count if histogram),
        min: (point.min if histogram),
        max: (point.max if histogram),
        details: details.compact.to_json
      }
    end
  end
end
