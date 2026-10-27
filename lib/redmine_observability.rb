require_relative 'redmine_observability/api_key_redactor'
require_relative 'redmine_observability/destinations'
require_relative 'redmine_observability/export_pipeline'
require_relative 'redmine_observability/extensions'

# Applies the plugin settings; +pipeline+ and +sampler+ stay nil without the initializer.
module RedmineObservability
  extend Extensions

  class << self
    attr_accessor :pipeline, :sampler

    def settings = Setting.plugin_redmine_observability || {}

    def destination_rows = Array(settings['destinations']).reject(&:blank?)

    # Runs on every request; does nothing when the destinations are unchanged.
    def apply_destinations
      return unless pipeline&.update(destination_rows)

      OpenTelemetry.tracer_provider.sampler = pipeline.empty? ? OpenTelemetry::SDK::Trace::Samplers::ALWAYS_OFF : sampler
    rescue StandardError => e
      Rails.logger.warn("redmine_observability: could not apply destinations: #{e.message}")
    end
  end

  # Settings are re-checked on each request, so every process picks up new destinations.
  module SettingCachePatch
    def check_cache
      super.tap { RedmineObservability.apply_destinations }
    end
  end
end
