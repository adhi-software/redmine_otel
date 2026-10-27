# ERPmine Observability - request, SQL and HTTP tracing for Redmine / ERPmine
# Copyright (C) 2026
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# Tracing starts in config/initializers/opentelemetry.rb, not here.

require_relative 'lib/redmine_observability'
# Already done by the initializer when it is loaded.
RedmineObservability.load_extensions

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
    'destinations' => []
  }
end

Setting.singleton_class.prepend(RedmineObservability::SettingCachePatch)

Rails.application.config.after_initialize { RedmineObservability.apply_destinations }
