# Redmine Observability

Redmine Observability is a plugin that helps you understand application performance and troubleshoot slow requests in Redmine and ERPmine. It uses [OpenTelemetry](https://opentelemetry.io) to trace incoming requests, SQL queries and outgoing HTTP calls, showing how each operation contributes to request processing time.

You can store traces in Redmine for review under **Administration > Traces**, send them to one or more tracing backends such as Jaeger, Zipkin, Grafana Tempo, OpenObserve, New Relic or Honeycomb, or use both options. Trace storage, retention and export destinations are managed through the plugin settings.

## Installation

1. Copy the plugin to `redmine/plugins/redmine_observability` and run `bundle install`.
2. Create the traces table: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`.
3. Restart Redmine.

Tracing starts with Rails on its own; `config/additional_environment.rb` needs no change. When upgrading from an earlier copy, the `redmine_observability` line added there can be removed.


## Uninstallation

Drop the traces table with `bundle exec rake redmine:plugins:migrate NAME=redmine_observability VERSION=0 RAILS_ENV=production`. Then delete `plugins/redmine_observability`, run `bundle install` and restart Redmine. Stop the tracing backend if nothing else uses it.

## Compatibility Matrix

| Redmine Version | Plugin Version |
|-----------------|----------------|
| 7.0.x           | 1.0            |

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
