# Redmine Observability

A plugin that records request, SQL and outgoing HTTP traces with [OpenTelemetry](https://opentelemetry.io) and sends them to one or more tracing backends at once, such as Jaeger, Zipkin, Grafana Tempo, OpenObserve, New Relic or Honeycomb. A backend only receives traces while it is running:

- Jaeger can be hosted by the plugin on the Redmine server, without Docker (see [Server hosting](#server-hosting)).
- Any other backend, such as Zipkin, Grafana Tempo or OpenObserve, you install and run yourself, on this server or another machine, then add as a destination.
- A cloud service, such as New Relic or Honeycomb, only needs a destination with your API key.

The Redmine API key that the mobile client sends as `?key=` is replaced with `[REDACTED]` before any trace leaves Redmine.

## Installation

- Extract the plugin into the `redmine/plugins` directory as `redmine_observability`.

- Install the gems
  ```sh
  bundle install
  ```

- Add this line to `config/additional_environment.rb` (create the file if it does not exist). The tracing setup must load with the Rails initializers; a plugin's `init.rb` runs too late.
  ```ruby
  config.paths['config/initializers'] << 'plugins/redmine_observability/config/initializers'
  ```

- Restart Redmine, then open **Administration → Plugins → Redmine Observability → Configure**.

## Recording and tracing

Add a row to **Destinations** for every backend that should receive traces; each one gets every span. Choosing a type fills in its usual endpoint and headers. Changes apply without a restart, and tracing is off while the list is empty.

| Type | Default endpoint | Headers |
|------|------------------|---------|
| Jaeger | `http://localhost:4318/v1/traces` | |
| Zipkin | `http://localhost:9411/api/v2/spans` (Zipkin protocol) | |
| OpenObserve | `http://localhost:5080/api/default/v1/traces` | `Authorization=Basic <Base64 of email:password>` |
| otel-desktop-viewer | `http://localhost:4318/v1/traces` | |
| Grafana Tempo | `http://localhost:4318/v1/traces` | |
| New Relic | `https://otlp.nr-data.net/v1/traces` | `api-key=<license key>` |
| Honeycomb | `https://api.honeycomb.io/v1/traces` | `x-honeycomb-team=<API key>` |
| Other OTLP backend | The backend's OTLP/HTTP traces URL | As the backend documents, e.g. for a Datadog Agent, Grafana Cloud, SigNoz or Elastic |

The endpoints are each backend's usual local address; change the host or port to wherever yours runs. Jaeger, otel-desktop-viewer and Grafana Tempo all use port 4318 by default, so only one of them can have it on a machine.

Headers are comma-separated `key=value` pairs. They are hidden in the list and filtered from the Redmine log.

## Server hosting

Tick **Host Jaeger** and click **Apply** to run Jaeger on this server; untick it to stop Jaeger. The table under it shows Jaeger's status, the address it receives traces at and a Start/Stop button; the name opens the Jaeger UI on port 16686. Add a Jaeger destination so traces reach it.

The first start downloads Jaeger into `~/.local/share/jaeger/<version>` and checks it against the SHA-256 the Jaeger project publishes. Logs go to `log/jaeger.log`. Jaeger keeps running when Redmine restarts; after the machine restarts, click **Start**. Traces are kept in memory, so they are lost when Jaeger stops.

Jaeger has no login. On a server reachable from other machines, keep its ports behind a firewall or a proxy.

To use another backend, instead of Jaeger or as well as it, install and run it yourself and add it under **Destinations**.

Jaeger can also be run from the command line:

```sh
plugins/redmine_observability/config/viewer jaeger start     # also: stop, status, install
```

## Configuration

| Variable | Purpose |
|----------|---------|
| `OTEL_SERVICE_NAME` | Name shown in the tracing backends; `redmine-erpmine` when not set. |
| `OTEL_TRACES_SAMPLER`, `OTEL_TRACES_SAMPLER_ARG` | Keep only part of the traces in production, e.g. `parentbased_traceidratio` and `0.1`. |
| `OBSERVABILITY_HOME` | Where the hosted Jaeger is installed; `~/.local/share` when not set. |

## Uninstallation

- Untick **Host Jaeger** under **Server hosting** and click **Apply**, so Jaeger stops.
- Remove the line from `config/additional_environment.rb`, delete `plugins/redmine_observability`, run `bundle install` and restart Redmine.
- Optionally delete the downloaded Jaeger in `~/.local/share/jaeger` and `tmp/observability`.

## Compatibility Matrix

| Redmine Version | Plugin Version |
|-----------------|----------------|
| 7.0.x           | 1.0          |

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
