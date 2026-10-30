# frozen_string_literal: true

require 'etc'

module RedmineObservability
  # Records request, SQL and process metrics, which DatabaseMetricExporter saves each minute.
  module Instruments
    # Bucket bounds in seconds: OpenTelemetry's advice for HTTP durations, and a finer set for SQL.
    REQUEST_BOUNDS = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10].freeze
    QUERY_BOUNDS = [0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5].freeze
    # db.operation.name values; any other statement counts as OTHER.
    OPERATIONS = %w[SELECT INSERT UPDATE DELETE].freeze
    # sql.active_record events that are not queries of Redmine's data.
    SKIPPED_QUERIES = %w[SCHEMA TRANSACTION].freeze
    # Linux only; elsewhere the memory gauge is left out.
    STATM = '/proc/self/statm'.freeze

    class << self
      def install(meter_provider)
        # Delta, so each saved point holds one interval and points add up across processes.
        histogram = OpenTelemetry::SDK::Metrics::Aggregation::ExplicitBucketHistogram
        meter_provider.add_view('http.server.request.duration',
                                aggregation: histogram.new(aggregation_temporality: :delta, boundaries: REQUEST_BOUNDS))
        meter_provider.add_view('db.client.operation.duration',
                                aggregation: histogram.new(aggregation_temporality: :delta, boundaries: QUERY_BOUNDS))

        meter = meter_provider.meter('redmine_observability')
        requests = meter.create_histogram('http.server.request.duration', unit: 's',
                                          description: 'Time to handle a request, per controller action')
        queries = meter.create_histogram('db.client.operation.duration', unit: 's', description: 'Time of a SQL query')
        meter.create_observable_gauge('process.thread.count', unit: '{thread}', description: 'Threads in each Redmine process',
                                      callback: -> { Thread.list.size })
        meter.create_observable_gauge('db.client.connection.count', unit: '{connection}', description: 'Database connections in use',
                                      callback: -> { ActiveRecord::Base.connection_pool.stat[:busy] })
        if File.readable?(STATM)
          meter.create_observable_gauge('process.memory.usage', unit: 'By', description: 'Resident memory of each Redmine process',
                                        callback: -> { resident_memory })
        end

        ActiveSupport::Notifications.monotonic_subscribe('process_action.action_controller') do |_name, start, finish, _id, payload|
          requests.record(finish - start, attributes: request_attributes(payload)) if storing?
        end
        ActiveSupport::Notifications.monotonic_subscribe('sql.active_record') do |_name, start, finish, _id, payload|
          next unless storing?
          next if payload[:cached] || SKIPPED_QUERIES.include?(payload[:name]) || OpenTelemetry::Common::Utilities.untraced?

          queries.record(finish - start, attributes: query_attributes(payload))
        end
      end

      private

      # Measurements are dropped while "Store metrics" is off, so none are taken.
      def storing? = RedmineObservability.metric_exporter&.enabled

      # A request that raised has no status yet; it gets the one Rails will answer with.
      def request_attributes(payload)
        status = payload[:status]
        status ||= ActionDispatch::ExceptionWrapper.status_code_for_exception(payload[:exception].first) if payload[:exception]
        { 'http.request.method' => payload[:method].to_s, 'http.route' => "#{payload[:controller]}##{payload[:action]}",
          'http.response.status_code' => status.to_i }
      end

      def query_attributes(payload)
        operation = payload[:sql].to_s[/\A\s*(\w+)/, 1]&.upcase
        { 'db.system' => payload[:connection]&.adapter_name.to_s.downcase,
          'db.operation.name' => OPERATIONS.include?(operation) ? operation : 'OTHER' }
      end

      def resident_memory
        File.read(STATM).split[1].to_i * Etc.sysconf(Etc::SC_PAGESIZE)
      end
    end
  end
end
