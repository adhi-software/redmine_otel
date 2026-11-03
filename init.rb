# frozen_string_literal: true

# ERPmine OpenTelemetry - request, SQL and HTTP traces, logs and metrics for Redmine / ERPmine
# Copyright (C) 2026
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

require_relative 'lib/redmine_opentelemetry'

# Keeps API keys out of the logs: destination headers and the ?key= the mobile client sends.
filters = Rails.application.config.filter_parameters
[:destinations, /\Akey\z/].each { |filter| filters << filter unless filters.include?(filter) }

Redmine::Plugin.register :redmine_opentelemetry do
  name 'Redmine OpenTelemetry'
  author 'Adhi Software Pvt Ltd'
  description 'Stores request, SQL and HTTP traces, logs and metrics in Redmine, and sends traces to tracing backends'
  version '1.0'
  author_url 'https://www.adhisoftware.co.in/'

  settings partial: 'settings/opentelemetry', default: {
    'destinations' => [],
    'store_traces' => '0',
    'traces_retention_days' => RedmineOpentelemetry::RETENTION_DAYS.to_s,
    'store_logs' => '0',
    'logs_retention_days' => RedmineOpentelemetry::RETENTION_DAYS.to_s,
    'stop_log_files' => '0',
    'store_metrics' => '0',
    'metrics_retention_days' => RedmineOpentelemetry::RETENTION_DAYS.to_s
  }
 
  menu :admin_menu, :ot_traces, { controller: 'ot_traces', action: 'index' },
       caption: :label_ot_opentelemetry, icon: 'stats', html: { class: 'icon icon-stats' }
end

Setting.singleton_class.prepend(RedmineOpentelemetry::SettingCachePatch)

# RedmineAgent::Runner is loaded by redmine_agent's init.rb, which runs before this one.
Rufus::Scheduler::Job.prepend(RedmineOpentelemetry::RufusJobTracing) if defined?(Rufus::Scheduler::Job)
RedmineAgent::Runner.singleton_class.prepend(RedmineOpentelemetry::AgentRunTracing) if defined?(RedmineAgent::Runner)

Rails.application.config.after_initialize { RedmineOpentelemetry.apply_settings }
