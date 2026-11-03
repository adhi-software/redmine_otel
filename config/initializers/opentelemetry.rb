# frozen_string_literal: true

# A Rails initializer, because init.rb runs too late for the Rack tracing middleware.

# The Gemfile requires lib/; Zeitwerk must skip it, or eager loading expects top-level constants there.
Rails.autoloaders.main.ignore(File.expand_path('../../lib', __dir__))

unless Rails.env.test?
  pipelines = RedmineOpentelemetry::Destinations::SIGNALS.index_with { RedmineOpentelemetry::ExportPipeline.new(_1) }
  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV['OTEL_SERVICE_NAME'].presence || 'Redmine OpenTelemetry'
    c.logger = Logger.new($stdout, level: ENV['OTEL_LOG_LEVEL'].presence || Logger::WARN)
    c.add_span_processor(RedmineOpentelemetry::ApiKeyRedactor.new)
    c.add_span_processor(pipelines[:traces])
    c.add_log_record_processor(pipelines[:logs])
    c.add_metric_reader(OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(exporter: pipelines[:metrics], export_interval_millis: 60_000))
    c.use_all
  end
  RedmineOpentelemetry.pipelines = pipelines
  ActiveSupport::Notifications.subscribe('sql.active_record', RedmineOpentelemetry::SqlSubscriber.new(RedmineOpentelemetry.tracer))
  RedmineOpentelemetry::Instruments.install(OpenTelemetry.meter_provider)
  Rails.logger.broadcast_to(RedmineOpentelemetry.log_bridge = RedmineOpentelemetry::LogBridge.new)
  RedmineOpentelemetry.log_files = RedmineOpentelemetry::LogFileMute.install(Rails.logger)
  RedmineOpentelemetry.sampler = RedmineOpentelemetry::RootFilter.new(OpenTelemetry.tracer_provider.sampler)
  OpenTelemetry.tracer_provider.sampler = OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF
end
