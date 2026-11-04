# Redmine OpenTelemetry

Redmine OpenTelemetry is a plugin that helps you understand application performance and troubleshoot slow requests in Redmine and ERPmine. It uses [OpenTelemetry](https://opentelemetry.io) to trace incoming requests, SQL queries and outgoing HTTP calls, showing how each operation contributes to request processing time, and records Redmine's logs and metrics alongside them.

**Administration > Redmine OpenTelemetry** has three tabs:

- **Traces**: each request or background job, with a waterfall of its SQL queries and HTTP calls.
- **Logs**: every line Redmine writes to its log, from Redmine's own log level (`config.log_level`), filterable by level, text and time. Each line keeps the trace of the request that wrote it, so a trace links to its log lines and a log line to its trace.
- **Metrics**: request durations per controller action, SQL query durations, threads, database connections in use and, on Linux, process memory, saved every minute and charted over time.

## Installation

1. Copy the plugin to `redmine/plugins/redmine_otel` and run `bundle install`.
2. Create the traces, logs and metrics tables: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`.
3. Restart Redmine.

Tracing starts with Rails on its own; `config/additional_environment.rb` needs no change.

## Uninstallation

Drop the plugin's tables with `bundle exec rake redmine:plugins:migrate NAME=redmine_otel VERSION=0 RAILS_ENV=production`. Then delete `plugins/redmine_otel`, run `bundle install` and restart Redmine. Stop the tracing backend if nothing else uses it.

## Compatibility Matrix

| Redmine Version | Plugin Version |
|-----------------|----------------|
| 7.0.x           | 1.0            |

## Release

OpenTelemetry based tracing, logging, and metrics for Redmine.

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
