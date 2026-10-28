require_relative 'database_exporter'
require_relative 'destinations'
require_relative 'export_pipeline'

# Applies the plugin settings; +pipeline+ and +sampler+ stay nil without the initializer.
module RedmineObservability
  # Days a stored trace is kept when the setting is blank.
  RETENTION_DAYS = 3
  # Marks a span that starts a trace for background work; see RootFilter.
  BACKGROUND_JOB = 'background.job'

  class << self
    attr_accessor :pipeline, :sampler

    def tracer = OpenTelemetry.tracer_provider.tracer('redmine_observability')

    def settings = Setting.plugin_redmine_observability || {}

    def store_traces? = settings['store_traces'] == '1'

    def retention_days
      days = settings['retention_days'].to_i
      days.positive? ? days : RETENTION_DAYS
    end

    # The saved destinations, plus the database when traces are stored in Redmine.
    def destination_rows
      rows = Array(settings['destinations']).reject(&:blank?)
      store_traces? ? [*rows, Destinations::DATABASE_ROW] : rows
    end

    # Runs on every request; does nothing when the destinations are unchanged.
    def apply_destinations
      return unless pipeline&.update(destination_rows)

      OpenTelemetry.tracer_provider.sampler = pipeline.empty? ? OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF : sampler
    rescue StandardError => e
      Rails.logger.warn("redmine_observability: could not apply destinations: #{e.message}")
    end
  end

  # Settings are re-checked on each request, so every process picks up new destinations.
  module SettingCachePatch
    def check_cache
      super.tap { RedmineObservability.apply_destinations }
    end
  end

  # Hides the ?key= API key, which the mobile client sends, in URL span attributes.
  class ApiKeyRedactor
    URL_ATTRIBUTES = %w[http.target http.url url.full url.query].freeze

    def on_start(span, _parent_context)
      attrs = span.attributes or return
      URL_ATTRIBUTES.each do |name|
        value = attrs[name]
        next unless value.is_a?(String) && value.include?('key=')

        span.set_attribute(name, value.gsub(/(\bkey=)[^&]*/, '\1[REDACTED]'))
      end
    end

    def on_finish(_span); end

    def force_flush(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS

    def shutdown(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS
  end

  # Starts a trace only at a request, a job or a span marked with BACKGROUND_JOB, so SQL
  # from boot or a background poll is dropped instead of saved one query per trace.
  class RootFilter
    ROOT_KINDS = %i[server consumer].freeze

    def initialize(sampler)
      @sampler = sampler
    end

    def should_sample?(trace_id:, parent_context:, links:, name:, kind:, attributes:)
      parent = OpenTelemetry::Trace.current_span(parent_context).context
      unless parent.valid? || ROOT_KINDS.include?(kind) || attributes&.key?(BACKGROUND_JOB)
        return OpenTelemetry::SDK::Trace::Samplers::Result.new(decision: OpenTelemetry::SDK::Trace::Samplers::Decision::DROP,
                                                               tracestate: parent.tracestate)
      end

      @sampler.should_sample?(trace_id: trace_id, parent_context: parent_context, links: links, name: name, kind: kind, attributes: attributes)
    end

    def description = "RootFilter{#{@sampler.description}}"
  end

  # Each run of a Rufus job is one trace. A job scheduled with trace: false, such as
  # a check every minute that usually finds nothing to do, gets none.
  module RufusJobTracing
    def do_call(time, do_rescue)
      return super if opts[:trace] == false

      path, line = callable.source_location
      attributes = { BACKGROUND_JOB => 'rufus', 'rufus.schedule' => original.to_s, 'code.filepath' => path, 'code.lineno' => line }.compact
      RedmineObservability.tracer.in_span(path ? "Rufus #{File.basename(path)}:#{line}" : 'Rufus job', attributes: attributes) { super }
    end
  end

  # An agent run works on its own thread, after its tick or request has ended, so it is
  # a trace of its own; the chat request it posts joins that trace.
  module AgentRunTracing
    def run(agent, stamp)
      attributes = { BACKGROUND_JOB => 'redmine_agent', 'agent.key' => agent['key'].to_s, 'agent.stamp' => stamp.to_s }
      RedmineObservability.tracer.in_span('RedmineAgent run', attributes: attributes) { super }
    end
  end

  # Traces SQL from Rails' sql.active_record events, for any database adapter.
  class SqlSubscriber
    # Adapter name => [db.system, dialect for hiding literals].
    DATABASES = {
      'postgresql' => ['postgresql', :postgres],
      'mysql2' => ['mysql', :mysql],
      'trilogy' => ['mysql', :mysql],
      'sqlserver' => ['mssql', :default],
      'sqlite' => ['sqlite', :sqlite]
    }.freeze

    def initialize(tracer)
      @tracer = tracer
    end

    # Query cache hits are skipped, since they never reach the database.
    def start(_name, _id, payload)
      return if payload[:cached]

      adapter = payload[:connection].adapter_name.downcase
      system, dialect = DATABASES[adapter] || [adapter, :default]
      span = @tracer.start_span(payload[:name].presence || 'SQL', kind: :client, attributes: { 'db.system' => system })
      # Literals become ?, so API keys are not stored; skipped when not recording.
      span.set_attribute('db.statement', OpenTelemetry::Helpers::SqlProcessor.obfuscate_sql(payload[:sql].to_s, adapter: dialect)) if span.recording?
      payload[:ob_span] = span
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: 'redmine_observability: could not trace a query')
    end

    def finish(_name, _id, payload)
      span = payload.delete(:ob_span) or return
      if (error = payload[:exception_object])
        span.record_exception(error)
        span.status = OpenTelemetry::Trace::Status.error(error.class.name)
      end
      span.finish
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: 'redmine_observability: could not trace a query')
    end
  end

  # Loads config/initializers/observability.rb with Redmine's; Bundler requires this file via the Gemfile.
  class Railtie < Rails::Railtie
    config.before_initialize do |app|
      app.paths['config/initializers'] << File.join(app.config.redmine_plugins_directory, 'redmine_observability/config/initializers')
    end
  end
end
