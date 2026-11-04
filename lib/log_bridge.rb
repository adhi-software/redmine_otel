# frozen_string_literal: true

module RedmineOtel
  # A Rails.logger broadcast that turns each log line into an OpenTelemetry log record of the
  # current trace; at OFF it records nothing.
  class LogBridge < ActiveSupport::Logger
    OFF = ::Logger::UNKNOWN + 1
    LEVEL_NAMES = %w[debug info warn error fatal].freeze
    COLOUR_CODES = /\e\[[\d;]*m/

    def initialize
      super(nil, level: OFF)
      @otel_logger = OpenTelemetry.logger_provider.logger(name: 'redmine_otel')
    end

    # Never raises or logs, since it runs inside every Rails.logger call.
    def add(severity, message = nil, progname = nil)
      severity ||= ::Logger::UNKNOWN
      return true if severity < level || OpenTelemetry::Common::Utilities.untraced?

      message = block_given? ? yield : progname if message.nil?
      body = text(message)
      return true if body.empty?

      name = LEVEL_NAMES[severity]
      @otel_logger.on_emit(timestamp: Time.now, severity_number: RedmineOtel::LOG_LEVELS[name],
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

  # Extended onto Rails.logger's file broadcasts, such as log/production.log. While log_files_off
  # is set they write nothing but keep their level, so the bridge still gets each line.
  module LogFileMute
    def add(severity, message = nil, progname = nil)
      RedmineOtel.log_files_off ? true : super
    end

    def <<(message)
      super unless RedmineOtel.log_files_off
    end

    # Returns the paths of the broadcasts it extends.
    def self.install(logger)
      logger.broadcasts.filter_map do |broadcast|
        path = broadcast.instance_variable_get(:@logdev).try(:filename)
        broadcast.extend(self) if path
        path
      end
    end
  end
end
