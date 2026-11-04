# frozen_string_literal: true

require_relative 'destinations'

module RedmineOtel
  # Sends one signal to every destination that takes it: spans and log records through a batch
  # processor per destination, metrics to each destination's exporter. #update swaps them live.
  class ExportPipeline
    def initialize(signal)
      @signal = signal
      @rows = nil
      @targets = [].freeze
      @mutex = Mutex.new
    end

    def empty? = @targets.empty?

    # Returns false when +rows+ are unchanged; old targets flush in the background.
    def update(rows)
      @mutex.synchronize do
        return false if rows == @rows

        previous = @targets
        @targets = rows.filter_map { |text| build(text) }.freeze
        @rows = rows
        Thread.new { previous.each { _1.shutdown(timeout: 5) } } if previous.any?
        true
      end
    end

    def on_start(span, parent_context) = @targets.each { _1.on_start(span, parent_context) }

    def on_finish(span) = @targets.each { _1.on_finish(span) }

    def on_emit(log_record, context) = @targets.each { _1.on_emit(log_record, context) }

    # Untraced, since the OTLP metrics exporter does not mark its own request.
    def export(metrics, timeout: nil)
      OpenTelemetry::Common::Utilities.untraced { combine(@targets.map { _1.export(metrics, timeout: timeout) }) }
    end

    def force_flush(timeout: nil) = combine(@targets.map { _1.force_flush(timeout: timeout) })

    def shutdown(timeout: nil) = combine(@targets.map { _1.shutdown(timeout: timeout) })

    private

    def build(text)
      row = Destinations::Row.parse(text)
      Destinations.target(row, @signal)
    rescue StandardError => e
      # Never the whole text: its headers hold API keys.
      OpenTelemetry.handle_error(exception: e, message: "redmine_otel: skipped #{@signal} destination #{row&.name.presence || row&.format}")
      nil
    end

    # Every signal's SDK uses the same SUCCESS and FAILURE codes.
    def combine(results)
      export = OpenTelemetry::SDK::Trace::Export
      results.all?(export::SUCCESS) ? export::SUCCESS : export::FAILURE
    end
  end
end
