# ERPmine Observability - request, SQL and HTTP tracing for Redmine / ERPmine
# Copyright (C) 2026
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# Tracing starts from config/initializers/opentelemetry.rb, which
# config/additional_environment.rb loads with the Rails initializers.

require_relative 'lib/redmine_observability'

# Destination rows carry API keys in their headers; keep them out of the logs.
filters = Rails.application.config.filter_parameters
filters << :destinations unless filters.include?(:destinations)

Redmine::Plugin.register :redmine_observability do
  name 'Redmine Observability'
  author 'Adhi Software Pvt Ltd'
  description 'Sends request, SQL and HTTP traces to one or more tracing backends, and hosts trace viewers such as Jaeger'
  version '1.1.0'
  requires_redmine version_or_higher: '6.0.0'
  author_url 'http://www.adhisoftware.co.in/'

  settings partial: 'settings/redmine_observability_settings', default: {
    # Rows of "type|endpoint|headers"; every span goes to each one.
    'destinations' => [],
    # Keys of RedmineObservability::Viewers::ALL to run on this server.
    'hosted_viewers' => []
  }
end

Setting.singleton_class.prepend(RedmineObservability::SettingCachePatch)
SettingsController.prepend(RedmineObservability::SettingsControllerPatch)

Rails.application.config.after_initialize { RedmineObservability.refresh }
