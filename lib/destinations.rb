require 'json'
require 'uri'

module RedmineObservability
  # Saved rows are JSON with name, format, endpoint and headers.
  module Destinations
    # +exporter+ is a proc (endpoint, headers) -> span exporter; +endpoint+ is an example.
    Format = Struct.new(:key, :label, :endpoint, :exporter, keyword_init: true)

    # Older rows are "type|endpoint|headers" or JSON with a type.
    Row = Struct.new(:name, :format, :endpoint, :headers) do
      def self.parse(text)
        text = text.to_s
        data = text.start_with?('{') ? JSON.parse(text) : %w[type endpoint headers].zip(text.split('|', 3)).to_h
        data['format'] ||= data['type'] == 'zipkin' ? 'zipkin' : 'otlp'
        new(*data.values_at(*members.map(&:to_s)).map { _1.to_s.strip })
      end
    end

    FORMATS = [
      Format.new(key: 'otlp', label: 'OTLP', endpoint: 'http://localhost:4318/v1/traces',
                 exporter: ->(endpoint, headers) { OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: endpoint, headers: headers) }),
      Format.new(key: 'zipkin', label: 'Zipkin', endpoint: 'http://localhost:9411/api/v2/spans',
                 exporter: ->(endpoint, headers) { OpenTelemetry::Exporter::Zipkin::Exporter.new(endpoint: endpoint, headers: headers) })
    ].freeze

    # Redmine's own database; set by "Store traces", so not in the dialog.
    DATABASE = Format.new(key: 'database', label: 'Redmine database', endpoint: nil,
                          exporter: ->(_endpoint, _headers) { DatabaseExporter.new })
    DATABASE_ROW = { name: 'Redmine', format: DATABASE.key }.to_json.freeze

    def self.formats = FORMATS

    def self.find_format(key) = key == DATABASE.key ? DATABASE : formats.find { _1.key == key }

    def self.label(key) = find_format(key)&.label || key

    def self.processor(row)
      exporter = find_format(row.format)&.exporter || raise(ArgumentError, "unknown format #{row.format}")
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter.call(row.endpoint, parse_headers(row.headers)))
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
