module RedmineObservability
  # Options added in instrumentations/, e.g. pg.rb defining Pg; see Extensions.
  module Instrumentations
    # +name+ is the class name, e.g. 'OpenTelemetry::Instrumentation::PG'.
    Config = Struct.new(:name, :options, keyword_init: true)
  end
end
