require 'base64'
require 'uri'
require_relative 'viewers'

module RedmineObservability
  # Backends offered under Recording and tracing. A saved row is
  # "type|endpoint|headers", headers written as key=value pairs joined by commas.
  module Destinations
    Type = Struct.new(:key, :label, :protocol, :endpoint, :headers, keyword_init: true)

    Row = Struct.new(:type, :endpoint, :headers) do
      def self.parse(text) = new(*text.to_s.split('|', 3).map(&:strip))
    end

    SERVICES = [
      Type.new(key: 'new_relic', label: 'New Relic', protocol: :otlp,
               endpoint: 'https://otlp.nr-data.net/v1/traces', headers: 'api-key='),
      Type.new(key: 'honeycomb', label: 'Honeycomb', protocol: :otlp,
               endpoint: 'https://api.honeycomb.io/v1/traces', headers: 'x-honeycomb-team='),
      Type.new(key: 'otlp', label: 'Other OTLP backend', protocol: :otlp, endpoint: '', headers: '')
    ].freeze

    # The hosted viewers first, with their local endpoints, then hosted services.
    # OpenObserve's default header carries the login of the instance hosted here.
    def self.types
      viewers = Viewers::ALL.values.map do |viewer|
        headers = viewer.key == 'openobserve' ? "Authorization=Basic #{Base64.strict_encode64(Viewers.openobserve_login.join(':'))}" : ''
        Type.new(key: viewer.key, label: viewer.label, protocol: viewer.protocol, endpoint: viewer.receives, headers: headers)
      end
      viewers + SERVICES
    end

    def self.label(key) = (Viewers::ALL[key]&.label || SERVICES.find { _1.key == key }&.label || key)

    def self.processor(row)
      headers = parse_headers(row.headers)
      exporter = if Viewers::ALL[row.type]&.protocol == :zipkin
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
