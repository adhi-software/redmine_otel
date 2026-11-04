# frozen_string_literal: true

require 'etc'

module RedmineOtel
  # Records request, SQL and process metrics, which DatabaseMetricExporter saves each minute.
  module Instruments
    # Histogram bucket bounds, in seconds.
    REQUEST_BOUNDS = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10].freeze
    QUERY_BOUNDS = [0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5].freeze
    OPERATIONS = %w[SELECT INSERT UPDATE DELETE].freeze
    SKIPPED_QUERIES = %w[SCHEMA TRANSACTION].freeze
    STATM = '/proc/self/statm'

    class << self
      def install(meter_provider)
        histogram = OpenTelemetry::SDK::Metrics::Aggregation::ExplicitBucketHistogram
        meter_provider.add_view('http.server.request.duration',
                                aggregation: histogram.new(aggregation_temporality: :delta, boundaries: REQUEST_BOUNDS))
        meter_provider.add_view('db.client.operation.duration',
                                aggregation: histogram.new(aggregation_temporality: :delta, boundaries: QUERY_BOUNDS))

        meter = meter_provider.meter('redmine_otel')
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
          requests.record(finish - start, attributes: request_attributes(payload)) if RedmineOtel.record_metrics
        end
        ActiveSupport::Notifications.monotonic_subscribe('sql.active_record') do |_name, start, finish, _id, payload|
          next unless RedmineOtel.record_metrics
          next if payload[:cached] || SKIPPED_QUERIES.include?(payload[:name]) || OpenTelemetry::Common::Utilities.untraced?

          queries.record(finish - start, attributes: query_attributes(payload))
        end
      end

      private

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
