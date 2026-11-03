# frozen_string_literal: true

require 'json'
require 'uri'

module RedmineOpentelemetry
  # Export destinations, saved as JSON rows of name, format, endpoint, headers and the logs and metrics flags.
  module Destinations
    SIGNALS = [:traces, :logs, :metrics].freeze

    # +name+ and +endpoint+ are placeholders for the settings dialog; +exporters+ maps each signal
    # the format can send to a proc (endpoint, headers) that builds its exporter.
    Format = Struct.new(:key, :label, :name, :endpoint, :exporters, keyword_init: true) do
      def signals = exporters.keys
    end

    # Traces always go to a destination; logs and metrics are '1' when sent too.
    Row = Struct.new(:name, :format, :endpoint, :headers, :logs, :metrics) do
      def self.parse(text)
        new(*JSON.parse(text.to_s).values_at(*members.map(&:to_s)).map { _1.to_s.strip })
      end

      def sends?(signal) = signal == :traces || self[signal] == '1'
    end

    FORMATS = [
      Format.new(key: 'otlp', label: 'OTLP', name: 'Jaeger', endpoint: 'http://localhost:4318/v1/traces',
                 exporters: {
                   traces: ->(endpoint, headers) { OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: endpoint, headers: headers) },
                   logs: ->(endpoint, headers) { OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(endpoint: endpoint, headers: headers) },
                   metrics: ->(endpoint, headers) { OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(endpoint: endpoint, headers: headers) }
                 }),
      Format.new(key: 'zipkin', label: 'Zipkin', name: 'Zipkin', endpoint: 'http://localhost:9411/api/v2/spans',
                 exporters: {
                   traces: ->(endpoint, headers) { OpenTelemetry::Exporter::Zipkin::Exporter.new(endpoint: endpoint, headers: headers) }
                 })
    ].freeze

    # Used while a "Store" setting is on, so not offered in the dialog.
    DATABASE = Format.new(key: 'database', label: 'Redmine database', endpoint: nil,
                          exporters: { traces: ->(*) { DatabaseExporter.new }, logs: ->(*) { DatabaseLogExporter.new },
                                       metrics: ->(*) { DatabaseMetricExporter.new } })
    DATABASE_ROW = { name: 'Redmine', format: DATABASE.key, logs: '1', metrics: '1' }.to_json.freeze

    def self.formats = FORMATS

    def self.find_format(key) = key == DATABASE.key ? DATABASE : formats.find { _1.key == key }

    def self.label(key) = find_format(key)&.label || key

    # The signals +row+ sends that its format supports.
    def self.signals(row)
      supported = find_format(row.format)&.signals || []
      SIGNALS.select { supported.include?(_1) && row.sends?(_1) }
    end

    # The span processor, log record processor or metric exporter that sends +signal+ to +row+;
    # nil when the row does not send it.
    def self.target(row, signal)
      raise ArgumentError, "unknown format #{row.format}" unless find_format(row.format)
      return unless signals(row).include?(signal)

      endpoint = signal == :traces ? row.endpoint : signal_endpoint(row.endpoint, signal)
      exporter = find_format(row.format).exporters[signal].call(endpoint, parse_headers(row.headers))
      case signal
      when :traces then OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
      when :logs then OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter)
      else exporter
      end
    end

    # The traces endpoint with /v1/logs or /v1/metrics in place of /v1/traces, as OTLP backends expect.
    def self.signal_endpoint(endpoint, signal)
      "#{endpoint.to_s.chomp('/').delete_suffix('/v1/traces')}/v1/#{signal}"
    end

    # Splits on the first "=" only, so Base64 padding in a value survives.
    def self.parse_headers(text)
      text.to_s.split(',').filter_map do |pair|
        key, value = pair.split('=', 2).map { URI.decode_uri_component(_1.to_s.strip) }
        [key, value.to_s] unless key.empty?
      end.to_h
    end
  end
end
