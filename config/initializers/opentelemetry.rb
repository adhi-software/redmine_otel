# Must load as a Rails initializer (see config/additional_environment.rb):
# plugin init.rb runs after the middleware stack is built, too late for the
# Rack middleware that starts each request's trace.

# Zeitwerk is not set up yet when initializers run, and the SDK keeps the
# processors for the life of the process, so lib/ is required, not autoloaded.
plugin_lib = File.expand_path('../../lib', __dir__)
Rails.autoloaders.main.ignore(plugin_lib)
require File.join(plugin_lib, 'redact_api_key_span_processor')
require File.join(plugin_lib, 'redmine_observability')

# Destinations come from the plugin settings, which cannot be read this early.
# Nothing is sampled until RedmineObservability.refresh finds at least one.
unless Rails.env.test?
  # Skip the per-instrumentation "successfully installed" lines at boot;
  # OTEL_LOG_LEVEL=info brings them back.
  OpenTelemetry.logger = Logger.new($stdout, level: ENV['OTEL_LOG_LEVEL'].presence || Logger::WARN)
  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV['OTEL_SERVICE_NAME'].presence || 'redmine-erpmine'
    c.add_span_processor(RedactApiKeySpanProcessor.new)
    c.add_span_processor(RedmineObservability.pipeline = RedmineObservability::ExportPipeline.new)
    c.use_all
  end
  RedmineObservability.sampler = OpenTelemetry.tracer_provider.sampler
  OpenTelemetry.tracer_provider.sampler = OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF
end
