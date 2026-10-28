# A Rails initializer, because init.rb runs too late for the Rack tracing middleware.

# The Gemfile requires lib/; Zeitwerk must skip it, or eager loading expects database_exporter.rb
# to define a top-level DatabaseExporter and production boot fails.
Rails.autoloaders.main.ignore(File.expand_path('../../lib', __dir__))

unless Rails.env.test?
  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV['OTEL_SERVICE_NAME'].presence || 'Redmine Observability'
    c.add_span_processor(RedmineObservability::ApiKeyRedactor.new)
    c.add_span_processor(RedmineObservability.pipeline = RedmineObservability::ExportPipeline.new)
    c.use_all
  end
  ActiveSupport::Notifications.subscribe('sql.active_record', RedmineObservability::SqlSubscriber.new(RedmineObservability.tracer))
  RedmineObservability.sampler = RedmineObservability::RootFilter.new(OpenTelemetry.tracer_provider.sampler)
  OpenTelemetry.tracer_provider.sampler = OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF
end
