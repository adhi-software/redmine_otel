require_relative 'destinations'
require_relative 'span_processors'
require_relative 'instrumentations'

module RedmineObservability
  # Add-on files in destinations/, span_processors/ and instrumentations/; see README.md.
  module Extensions
    # Once, in file name order; a broken file is logged and skipped.
    def load_extensions
      return if @extensions_loaded

      @extensions_loaded = true
      each_extension(Destinations, 'destinations') { add_destination_format(_1) }
      each_extension(SpanProcessors, 'span_processors') { add_span_processor(_1.new) }
      each_extension(Instrumentations, 'instrumentations') do |config|
        (instrumentation_config[config.name] ||= {}).merge!(config.options)
      end
    end

    def add_destination_format(format) = Destinations.add_format(format)

    def span_processors = @span_processors ||= []

    # +processor+ needs only the callbacks it uses; it runs after the API key is redacted.
    def add_span_processor(processor)
      guarded = GuardedProcessor.new(processor)
      span_processors << guarded
      # Already configured when called from a plugin's init.rb.
      OpenTelemetry.tracer_provider.add_span_processor(guarded) if pipeline
    end

    # Options for c.use_all, keyed by instrumentation name.
    def instrumentation_config = @instrumentation_config ||= {}

    private

    def each_extension(namespace, folder)
      Dir[File.join(__dir__, folder, '*.rb')].sort.each do |file|
        require file
        yield namespace.const_get(File.basename(file, '.rb').camelize, false)
      rescue StandardError, ScriptError => e
        Rails.logger.error("redmine_observability: skipped #{file}: #{e.message}")
      end
    end
  end

  # Logs a processor's errors instead of letting the SDK fail the request with them.
  class GuardedProcessor
    def initialize(processor)
      @processor = processor
    end

    def on_start(span, parent_context) = forward(:on_start, span, parent_context)

    def on_finish(span) = forward(:on_finish, span)

    def force_flush(timeout: nil) = forward(:force_flush, timeout: timeout) || OpenTelemetry::SDK::Trace::Export::SUCCESS

    def shutdown(timeout: nil) = forward(:shutdown, timeout: timeout) || OpenTelemetry::SDK::Trace::Export::SUCCESS

    private

    def forward(callback, *args, **options)
      @processor.public_send(callback, *args, **options) if @processor.respond_to?(callback)
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: "redmine_observability: #{@processor.class}##{callback} failed")
      OpenTelemetry::SDK::Trace::Export::FAILURE
    end
  end
end
