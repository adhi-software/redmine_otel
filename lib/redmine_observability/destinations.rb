require 'uri'
require_relative 'viewers'

module RedmineObservability
  # Backends offered under Recording and tracing, each with its usual endpoint.
  # Jaeger can be hosted here; the admin installs and runs the others. A saved
  # row is "type|endpoint|headers", headers written as key=value pairs joined
  # by commas.
  module Destinations
    Type = Struct.new(:key, :label, :protocol, :endpoint, :headers, keyword_init: true)

    Row = Struct.new(:type, :endpoint, :headers) do
      def self.parse(text) = new(*text.to_s.split('|', 3).map(&:strip))
    end

    TYPES = [
      Type.new(key: 'jaeger', label: 'Jaeger', protocol: :otlp, endpoint: Viewers::ALL['jaeger'].receives, headers: ''),
      Type.new(key: 'zipkin', label: 'Zipkin', protocol: :zipkin,
               endpoint: 'http://localhost:9411/api/v2/spans', headers: ''),
      Type.new(key: 'openobserve', label: 'OpenObserve', protocol: :otlp,
               endpoint: 'http://localhost:5080/api/default/v1/traces', headers: 'Authorization=Basic '),
      Type.new(key: 'otel-desktop-viewer', label: 'otel-desktop-viewer', protocol: :otlp,
               endpoint: 'http://localhost:4318/v1/traces', headers: ''),
      Type.new(key: 'grafana-tempo', label: 'Grafana Tempo', protocol: :otlp,
               endpoint: 'http://localhost:4318/v1/traces', headers: ''),
      Type.new(key: 'new_relic', label: 'New Relic', protocol: :otlp,
               endpoint: 'https://otlp.nr-data.net/v1/traces', headers: 'api-key='),
      Type.new(key: 'honeycomb', label: 'Honeycomb', protocol: :otlp,
               endpoint: 'https://api.honeycomb.io/v1/traces', headers: 'x-honeycomb-team='),
      Type.new(key: 'otlp', label: 'Other OTLP backend', protocol: :otlp, endpoint: '', headers: '')
    ].freeze

    def self.type(key) = TYPES.find { _1.key == key }

    def self.label(key) = type(key)&.label || key

    def self.processor(row)
      headers = parse_headers(row.headers)
      exporter = if type(row.type)&.protocol == :zipkin
                   OpenTelemetry::Exporter::Zipkin::Exporter.new(endpoint: row.endpoint, headers: headers)
                 else
                   OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: row.endpoint, headers: headers)
                 end
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
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
