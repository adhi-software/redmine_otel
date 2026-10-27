# A Rails initializer, because init.rb runs too late for the Rack tracing middleware.

# Required, not autoloaded: Zeitwerk is not ready yet and the SDK keeps the processors.
plugin_lib = File.expand_path('../../lib', __dir__)
Rails.autoloaders.main.ignore(plugin_lib)
require File.join(plugin_lib, 'redmine_observability')

# Before configure, so extension processors and options are included.
RedmineObservability.load_extensions

# Sampling stays off until apply_destinations finds a saved destination.
unless Rails.env.test?
  # Hides the boot-time install lines; OTEL_LOG_LEVEL=info shows them.
  OpenTelemetry.logger = Logger.new($stdout, level: ENV['OTEL_LOG_LEVEL'].presence || Logger::WARN)
  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV['OTEL_SERVICE_NAME'].presence || 'redmine-erpmine'
    c.add_span_processor(RedmineObservability::ApiKeyRedactor.new)
    RedmineObservability.span_processors.each { c.add_span_processor(_1) }
    c.add_span_processor(RedmineObservability.pipeline = RedmineObservability::ExportPipeline.new)
    c.use_all(RedmineObservability.instrumentation_config)
  end
  RedmineObservability.sampler = OpenTelemetry.tracer_provider.sampler
  OpenTelemetry.tracer_provider.sampler = OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF
end
