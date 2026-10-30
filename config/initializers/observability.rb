# frozen_string_literal: true

# A Rails initializer, because init.rb runs too late for the Rack tracing middleware.

# The Gemfile requires lib/; Zeitwerk must skip it, or eager loading expects database_exporter.rb
# to define a top-level DatabaseExporter and production boot fails.
Rails.autoloaders.main.ignore(File.expand_path('../../lib', __dir__))

unless Rails.env.test?
  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV['OTEL_SERVICE_NAME'].presence || 'Redmine Observability'
    c.add_span_processor(RedmineObservability::ApiKeyRedactor.new)
    c.add_span_processor(RedmineObservability.pipeline = RedmineObservability::ExportPipeline.new)
    # Metrics and logs go only to the database, while "Store metrics" and "Store logs" are on.
    reader = OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
      exporter: RedmineObservability.metric_exporter = RedmineObservability::DatabaseMetricExporter.new,
      export_interval_millis: 60_000
    )
    c.add_metric_reader(reader)
    c.add_log_record_processor(OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(RedmineObservability::DatabaseLogExporter.new))
    c.use_all
  end
  ActiveSupport::Notifications.subscribe('sql.active_record', RedmineObservability::SqlSubscriber.new(RedmineObservability.tracer))
  RedmineObservability::Instruments.install(OpenTelemetry.meter_provider)
  Rails.logger.broadcast_to(RedmineObservability.log_bridge = RedmineObservability::LogBridge.new) if Rails.logger.respond_to?(:broadcast_to)
  RedmineObservability.sampler = RedmineObservability::RootFilter.new(OpenTelemetry.tracer_provider.sampler)
  OpenTelemetry.tracer_provider.sampler = OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF
end
