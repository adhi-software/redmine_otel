# ERPmine Observability - request, SQL and HTTP tracing for Redmine / ERPmine
# Copyright (C) 2026
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# Tracing starts in config/initializers/observability.rb, not here.

require_relative 'lib/redmine_observability'

# Destination headers hold API keys; keep them out of the logs.
filters = Rails.application.config.filter_parameters
filters << :destinations unless filters.include?(:destinations)

Redmine::Plugin.register :redmine_observability do
  name 'Redmine Observability'
  author 'Adhi Software Pvt Ltd'
  description 'Sends request, SQL and HTTP traces to one or more tracing backends'
  version '1.0'
  author_url 'http://www.adhisoftware.co.in/'

  settings partial: 'settings/observability', default: {
    # JSON rows of name, format, endpoint and headers; every span goes to each one.
    'destinations' => [],
    # '1' also saves every span to the database, shown under Administration > Redmine Observability.
    'store_traces' => '0',
    'retention_days' => RedmineObservability::RETENTION_DAYS.to_s
  }

  menu :admin_menu, :ob_traces, { controller: 'ob_traces', action: 'index' },
       caption: :label_ob_observability, icon: 'stats', html: { class: 'icon icon-stats' }
end

Setting.singleton_class.prepend(RedmineObservability::SettingCachePatch)

# Background work outside a request: Rufus is loaded by Bundler, the agent plugin's
# Runner by its init.rb, which runs before this one.
Rufus::Scheduler::Job.prepend(RedmineObservability::RufusJobTracing) if defined?(Rufus::Scheduler::Job)
RedmineAgent::Runner.singleton_class.prepend(RedmineObservability::AgentRunTracing) if defined?(RedmineAgent::Runner)

Rails.application.config.after_initialize { RedmineObservability.apply_destinations }
