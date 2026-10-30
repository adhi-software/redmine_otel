# frozen_string_literal: true

# ERPmine Observability - request, SQL and HTTP traces, logs and metrics for Redmine / ERPmine
# Copyright (C) 2026
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# Tracing starts in config/initializers/observability.rb, not here.

require_relative 'lib/redmine_observability'

# Keeps API keys out of the logs, and so out of stored log lines: destination headers, and the
# ?key= the mobile client sends. Only a parameter named exactly key, so api_key and the like stay readable.
filters = Rails.application.config.filter_parameters
[:destinations, /\Akey\z/].each { |filter| filters << filter unless filters.include?(filter) }

Redmine::Plugin.register :redmine_observability do
  name 'Redmine Observability'
  author 'Adhi Software Pvt Ltd'
  description 'Stores request, SQL and HTTP traces, logs and metrics in Redmine, and sends traces to tracing backends'
  version '1.0'
  author_url 'https://www.adhisoftware.co.in/'

  settings partial: 'settings/observability', default: {
    # JSON rows of name, format, endpoint and headers; every span goes to each one.
    'destinations' => [],
    # '1' saves that signal to the database, shown under Administration > Redmine Observability,
    # for its retention days.
    'store_traces' => '0',
    'traces_retention_days' => RedmineObservability::RETENTION_DAYS.to_s,
    'store_logs' => '0',
    'logs_retention_days' => RedmineObservability::RETENTION_DAYS.to_s,
    'store_metrics' => '0',
    'metrics_retention_days' => RedmineObservability::RETENTION_DAYS.to_s
  }

  menu :admin_menu, :ob_traces, { controller: 'ob_traces', action: 'index' },
       caption: :label_ob_observability, icon: 'stats', html: { class: 'icon icon-stats' }
end

Setting.singleton_class.prepend(RedmineObservability::SettingCachePatch)

# Background work outside a request: Rufus is loaded by Bundler, the agent plugin's
# Runner by its init.rb, which runs before this one.
Rufus::Scheduler::Job.prepend(RedmineObservability::RufusJobTracing) if defined?(Rufus::Scheduler::Job)
RedmineAgent::Runner.singleton_class.prepend(RedmineObservability::AgentRunTracing) if defined?(RedmineAgent::Runner)

Rails.application.config.after_initialize { RedmineObservability.apply_settings }
