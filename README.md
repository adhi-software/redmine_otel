# Redmine Observability

Records request, SQL and outgoing HTTP traces with [OpenTelemetry](https://opentelemetry.io) and sends them to one or more tracing backends, such as Jaeger, Zipkin, Grafana Tempo, OpenObserve, New Relic or Honeycomb.

## Installation

1. Copy the plugin to `redmine/plugins/redmine_observability` and run `bundle install`.
2. Add this line to `config/additional_environment.rb` (create the file if needed), so tracing starts with Rails:
   ```ruby
   config.paths['config/initializers'] << 'plugins/redmine_observability/config/initializers'
   ```
3. Restart Redmine.

The tracing backend is installed separately. For example, download [Jaeger](https://www.jaegertracing.io/download/) and run `./jaeger`; its UI opens at `http://localhost:16686`. Then open **Administration → Plugins → Redmine Observability → Configure** and add the backend under **Destinations**: any name, its format and its endpoint. Usual endpoints:

| Backend | Format | Endpoint | Headers |
|---------|--------|----------|---------|
| Jaeger, Grafana Tempo, otel-desktop-viewer | OTLP | `http://localhost:4318/v1/traces` | |
| OpenObserve | OTLP | `http://localhost:5080/api/default/v1/traces` | `Authorization=Basic <base64 user:password>` |
| New Relic | OTLP | `https://otlp.nr-data.net/v1/traces` | `api-key=<license key>` |
| Honeycomb | OTLP | `https://api.honeycomb.io/v1/traces` | `x-honeycomb-team=<API key>` |
| Zipkin | Zipkin | `http://localhost:9411/api/v2/spans` | |

In Jaeger, search with the tag `error=true` to find failed requests, or sort by **Longest First** to find slow ones.

## Uninstallation

Remove the line from `config/additional_environment.rb`, delete `plugins/redmine_observability`, run `bundle install` and restart Redmine. Stop the tracing backend if nothing else uses it.

## Compatibility Matrix

| Redmine Version | Plugin Version |
|-----------------|----------------|
| 7.0.x           | 1.0            |

## Extensions

Extend the plugin by adding files under `lib/redmine_observability/` instead of editing it. Each file defines one constant named after the file, e.g. `signoz.rb` defines `Signoz`. Restart Redmine after adding or changing a file. A file that fails to load is skipped and logged. Back up your files before upgrading the plugin.

| Folder | The file defines | Effect |
|--------|------------------|--------|
| `destinations/` | a `Destinations::Format` | Adds a format, or replaces the built-in format with the same key |
| `span_processors/` | a class with `on_start` and/or `on_finish` | Runs on every span; its errors are logged, not raised |
| `instrumentations/` | an `Instrumentations::Config` | Sets options for one instrumentation |

```ruby
# lib/redmine_observability/destinations/console.rb
module RedmineObservability
  module Destinations
    # Prints spans to Redmine's standard output, ignoring the endpoint.
    Console = Format.new(key: 'console', label: 'Console', endpoint: 'http://localhost/',
                         exporter: ->(_endpoint, _headers) { OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new })
  end
end

# lib/redmine_observability/span_processors/add_environment.rb
module RedmineObservability
  module SpanProcessors
    class AddEnvironment
      def on_start(span, _parent_context)
        span.set_attribute('deployment.environment', Rails.env)
      end
    end
  end
end

# lib/redmine_observability/instrumentations/pg.rb
module RedmineObservability
  module Instrumentations
    # Leaves SQL text out of the traces.
    Pg = Config.new(name: 'OpenTelemetry::Instrumentation::PG', options: { db_statement: :omit })
  end
end
```

- A format's `exporter:` is a proc that takes the endpoint and headers and returns a span exporter; `endpoint:` is the example shown in the dialog. The built-in formats are OTLP and Zipkin.
- Set span attributes in `on_start`; a span is read-only by `on_finish`. Use Redmine models only inside the callbacks, since they are not loaded when the file is read.
- To add an instrumentation, list its gem in `plugins/redmine_observability/PluginGemfile`, run `bundle install` and restart Redmine.

Another plugin can register destination formats and span processors from its own `init.rb`:

```ruby
RedmineObservability.add_destination_format(RedmineObservability::Destinations::Format.new(key: 'my_format', label: 'My format', endpoint: 'http://localhost:4318/v1/traces', exporter: ->(endpoint, headers) { MyPluginExporter.new(endpoint, headers) }))
RedmineObservability.add_span_processor(MyPluginSpanProcessor.new)
```

Instrumentation options only work from `instrumentations/`, because tracing starts before any plugin's `init.rb` runs.

---

## Customization

For any Customization/Support, please contact us, our consulting team will be happy to help you

Adhi Software Pvt Ltd<br>
12/B-35, 6th Cross Road<br>
SIPCOT IT Park, Siruseri<br>
Kancheepuram Dist<br>
Tamilnadu - 603103<br>
India

Website: [https://www.adhisoftware.co.in](https://www.adhisoftware.co.in)<br>
Email: info@adhisoftware.co.in<br>
Phone: +91 44 27470401
