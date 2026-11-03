# frozen_string_literal: true

require_relative 'database_exporter'
require_relative 'database_log_exporter'
require_relative 'database_metric_exporter'
require_relative 'destinations'
require_relative 'export_pipeline'
require_relative 'instruments'
require_relative 'log_bridge'

# Plugin settings and the tracing objects the initializer sets up; those stay nil without it.
module RedmineOpentelemetry
  RETENTION_DAYS = 3
  # Marks a span that starts a trace for background work; see RootFilter.
  BACKGROUND_JOB = 'background.job'
  # OpenTelemetry severity number of each Logger level, lowest first.
  LOG_LEVELS = { 'debug' => 5, 'info' => 9, 'warn' => 13, 'error' => 17, 'fatal' => 21 }.freeze

  class << self
    # +pipelines+ maps each of Destinations::SIGNALS to its ExportPipeline.
    attr_accessor :pipelines, :sampler, :log_bridge, :log_files_off, :record_metrics
    attr_writer :log_files

    # Log files LogFileMute can stop; none when Redmine logs to STDOUT.
    def log_files = @log_files || []

    def tracer = OpenTelemetry.tracer_provider.tracer('redmine_opentelemetry')

    def settings = Setting.plugin_redmine_opentelemetry || {}

    def store_traces? = settings['store_traces'] == '1'

    def store_logs? = settings['store_logs'] == '1'

    def stop_log_files? = settings['stop_log_files'] == '1'

    def store_metrics? = settings['store_metrics'] == '1'

    # Redmine's config.log_level, from Rails.logger's broadcasts other than the bridge.
    def log_level
      Rails.logger.broadcasts.reject { _1.equal?(log_bridge) }.map(&:level).min || ::Logger::INFO
    end

    def retention_days(signal)
      days = settings["#{signal}_retention_days"].to_i
      days.positive? ? days : RETENTION_DAYS
    end

    # The saved destinations, plus Redmine's database while it stores +signal+.
    def destination_rows(signal)
      rows = Array(settings['destinations']).reject(&:blank?)
      public_send(:"store_#{signal}?") ? [*rows, Destinations::DATABASE_ROW] : rows
    end

    # Runs on every request; the bridge, instruments and exporters read these values instead of
    # Setting, which may query the database.
    def apply_settings
      return unless pipelines

      changed = pipelines.filter_map { |signal, pipeline| signal if pipeline.update(destination_rows(signal)) }
      log_bridge.level = pipelines[:logs].empty? ? LogBridge::OFF : log_level
      self.log_files_off = store_logs? && stop_log_files?
      self.record_metrics = !pipelines[:metrics].empty?
      return unless changed.include?(:traces)

      OpenTelemetry.tracer_provider.sampler = pipelines[:traces].empty? ? OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF : sampler
    rescue StandardError => e
      Rails.logger.warn("redmine_opentelemetry: could not apply settings: #{e.message}")
    end
  end

  # Settings are re-checked on each request, so every process picks up changes.
  module SettingCachePatch
    def check_cache
      super.tap { RedmineOpentelemetry.apply_settings }
    end
  end

  # Hides the ?key= API key that the mobile client sends in URL span attributes.
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
    ROOT_KINDS = [:server, :consumer].freeze

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

  # One trace per Rufus job run, unless the job is scheduled with trace: false.
  module RufusJobTracing
    def do_call(time, do_rescue)
      return super if opts[:trace] == false

      path, line = callable.source_location
      attributes = { BACKGROUND_JOB => 'rufus', 'rufus.schedule' => original.to_s, 'code.filepath' => path, 'code.lineno' => line }.compact
      RedmineOpentelemetry.tracer.in_span(path ? "Rufus #{File.basename(path)}:#{line}" : 'Rufus job', attributes: attributes) { super }
    end
  end

  # An agent run is a trace of its own, since it runs on a thread after its tick or request has ended.
  module AgentRunTracing
    def run(agent, stamp)
      attributes = { BACKGROUND_JOB => 'redmine_agent', 'agent.key' => agent['key'].to_s, 'agent.stamp' => stamp.to_s }
      RedmineOpentelemetry.tracer.in_span('RedmineAgent run', attributes: attributes) { super }
    end
  end

  # Traces SQL from sql.active_record events, for any database adapter.
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

    def start(_name, _id, payload)
      return if payload[:cached]

      adapter = payload[:connection].adapter_name.downcase
      system, dialect = DATABASES[adapter] || [adapter, :default]
      span = @tracer.start_span(payload[:name].presence || 'SQL', kind: :client, attributes: { 'db.system' => system })
      span.set_attribute('db.statement', OpenTelemetry::Helpers::SqlProcessor.obfuscate_sql(payload[:sql].to_s, adapter: dialect)) if span.recording?
      payload[:ot_span] = span
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: 'redmine_opentelemetry: could not trace a query')
    end

    def finish(_name, _id, payload)
      span = payload.delete(:ot_span) or return
      if (error = payload[:exception_object])
        span.record_exception(error)
        span.status = OpenTelemetry::Trace::Status.error(error.class.name)
      end
      span.finish
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: 'redmine_opentelemetry: could not trace a query')
    end
  end

  # Loads config/initializers/opentelemetry.rb with Redmine's; Bundler requires this file via the Gemfile.
  class Railtie < Rails::Railtie
    config.before_initialize do |app|
      app.paths['config/initializers'] << File.join(app.config.redmine_plugins_directory, 'redmine_opentelemetry/config/initializers')
    end
  end
end
