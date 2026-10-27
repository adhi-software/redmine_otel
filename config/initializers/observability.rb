# A Rails initializer, because init.rb runs too late for the Rack tracing middleware.

# Required, not autoloaded: Zeitwerk is not ready yet and the SDK keeps the processors.
plugin_lib = File.expand_path('../../lib', __dir__)
Rails.autoloaders.main.ignore(plugin_lib)
require File.join(plugin_lib, 'redmine_observability')

# Sampling stays off until apply_destinations finds a saved destination.
unless Rails.env.test?
  # Hides the boot-time install lines; OTEL_LOG_LEVEL=info shows them.
  OpenTelemetry.logger = Logger.new($stdout, level: ENV['OTEL_LOG_LEVEL'].presence || Logger::WARN)
  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV['OTEL_SERVICE_NAME'].presence || 'Redmine Observability'
    c.add_span_processor(RedmineObservability::ApiKeyRedactor.new)
    c.add_span_processor(RedmineObservability.pipeline = RedmineObservability::ExportPipeline.new)
    c.use_all
  end
  ActiveSupport::Notifications.subscribe('sql.active_record', RedmineObservability::SqlSubscriber.new(OpenTelemetry.tracer_provider.tracer('redmine_observability')))
  RedmineObservability.sampler = OpenTelemetry.tracer_provider.sampler
  OpenTelemetry.tracer_provider.sampler = OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF
end
