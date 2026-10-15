require_relative 'destinations'

module RedmineObservability
  # Span processor that hands every span to one BatchSpanProcessor per
  # destination row. #update swaps that set while Redmine runs, so a change on
  # the settings page applies without a restart.
  class ExportPipeline
    def initialize
      @rows = nil
      @processors = [].freeze
      @mutex = Mutex.new
    end

    def empty? = @processors.empty?

    # Returns false when +rows+ are already applied. Replaced processors flush
    # their queued spans on a background thread, off the request.
    def update(rows)
      @mutex.synchronize do
        return false if rows == @rows

        previous = @processors
        @processors = rows.filter_map { |text| build(text) }.freeze
        @rows = rows
        Thread.new { previous.each { _1.shutdown(timeout: 5) } } if previous.any?
        true
      end
    end

    def on_start(span, parent_context) = @processors.each { _1.on_start(span, parent_context) }

    def on_finish(span) = @processors.each { _1.on_finish(span) }

    def force_flush(timeout: nil) = combine(@processors.map { _1.force_flush(timeout: timeout) })

    def shutdown(timeout: nil) = combine(@processors.map { _1.shutdown(timeout: timeout) })

    private

    def build(text)
      Destinations.processor(Destinations::Row.parse(text))
    rescue StandardError => e
      OpenTelemetry.handle_error(exception: e, message: "redmine_observability: skipped destination #{text.split('|', 2).first}")
      nil
    end

    def combine(results)
      export = OpenTelemetry::SDK::Trace::Export
      results.all?(export::SUCCESS) ? export::SUCCESS : export::FAILURE
    end
  end
end
