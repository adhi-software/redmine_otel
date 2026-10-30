# frozen_string_literal: true

module RedmineObservability
  # One of Rails.logger's broadcasts: each line it logs becomes an OpenTelemetry log record,
  # with the trace and span of the request that logged it. RedmineObservability.apply_settings
  # sets the level; at OFF nothing is recorded and Rails.logger's own level is unchanged.
  class LogBridge < ActiveSupport::Logger
    OFF = ::Logger::UNKNOWN + 1
    # Logger severities DEBUG to FATAL, by number.
    LEVEL_NAMES = %w[debug info warn error fatal].freeze
    # Terminal colour codes, which Rails adds to SQL lines in development.
    COLOUR_CODES = /\e\[[\d;]*m/

    def initialize
      super(nil, level: OFF)
      @otel_logger = OpenTelemetry.logger_provider.logger(name: 'redmine_observability')
    end

    # Never raises or logs, since it runs inside every Rails.logger call.
    def add(severity, message = nil, progname = nil)
      severity ||= ::Logger::UNKNOWN
      # Exporters save untraced; their own SQL lines are not recorded again.
      return true if severity < level || OpenTelemetry::Common::Utilities.untraced?

      message = block_given? ? yield : progname if message.nil?
      body = text(message)
      return true if body.empty?

      name = LEVEL_NAMES[severity]
      @otel_logger.on_emit(timestamp: Time.now, severity_number: RedmineObservability::LOG_LEVELS[name],
                           severity_text: name&.upcase || 'UNKNOWN', body: body, attributes: exception_attributes(message))
      true
    rescue StandardError
      true
    end

    private

    def text(message)
      text = case message
             when ::String then message
             when ::Exception then "#{message.message} (#{message.class})\n#{Array(message.backtrace).join("\n")}"
             else message.inspect
             end
      text.scrub.gsub(COLOUR_CODES, '').strip
    end

    def exception_attributes(message)
      return unless message.is_a?(::Exception)

      { 'exception.type' => message.class.name, 'exception.message' => message.message.to_s }
    end
  end
end
