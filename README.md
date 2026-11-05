# Redmine OpenTelemetry

Redmine OpenTelemetry is an observability plugin for Redmine, including its installed plugins. Built on [OpenTelemetry](https://opentelemetry.io), it traces incoming requests, SQL queries and outgoing HTTP calls, and collects Redmine's logs and metrics, so you can find bottlenecks and investigate issues from one place.

## Key Features

Everything is under **Administration > Redmine OpenTelemetry**:

- **Traces**: each request and background job, with a waterfall of its SQL queries and HTTP calls that shows where the time goes.
- **Logs**: Redmine's application log, filterable by level, text and time. Each entry links to the trace of the request that wrote it.
- **Metrics**: request durations per controller action, SQL query durations, threads, database connections in use and, on Linux, process memory, collected every minute and charted over time.

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
