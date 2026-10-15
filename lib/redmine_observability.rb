require_relative 'redmine_observability/viewers'
require_relative 'redmine_observability/destinations'
require_relative 'redmine_observability/export_pipeline'

# Reads the plugin settings and applies them. +pipeline+ and +sampler+ are set by
# config/initializers/opentelemetry.rb and stay nil when it is not loaded.
module RedmineObservability
  class << self
    attr_accessor :pipeline, :sampler

    def settings = Setting.plugin_redmine_observability || {}

    def destination_rows = Array(settings['destinations']).reject(&:blank?)

    def hosted_viewers = Array(settings['hosted_viewers']).filter_map { Viewers::ALL[_1] }

    # Points the pipeline at the saved destinations and samples nothing while
    # there are none. Cheap when they are unchanged; runs on every request.
    def refresh
      return unless pipeline&.update(destination_rows)

      OpenTelemetry.tracer_provider.sampler = pipeline.empty? ? OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF : sampler
    rescue StandardError => e
      Rails.logger.warn("redmine_observability: could not apply destinations: #{e.message}")
    end
  end

  # Redmine checks for changed settings at the start of each request, so every
  # app process picks up a new destination list there.
  module SettingCachePatch
    def check_cache
      super.tap { RedmineObservability.refresh }
    end
  end

  # Saving the settings starts Jaeger when Host Jaeger is ticked and stops it
  # when it is not.
  module SettingsControllerPatch
    def plugin
      return super unless request.post? && params[:id] == 'redmine_observability'

      before = RedmineObservability.hosted_viewers
      super
      hosted = RedmineObservability.hosted_viewers
      (before - hosted).each { Viewers.stop(_1) }
      hosted.each { Viewers.start_in_background(_1) if Viewers.status(_1) == :stopped }
    end
  end
end
