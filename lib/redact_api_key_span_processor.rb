# Removes the Redmine API key from URL span attributes before export; the
# mobile client sends it as ?key=. Required by config/initializers/opentelemetry.rb.
class RedactApiKeySpanProcessor
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
