require 'digest'
require 'fileutils'
require 'rbconfig'
require 'securerandom'
require 'tmpdir'

module RedmineObservability
  # Trace viewers the plugin can host on this machine: what to download, how to
  # run each one and the ports it uses, chosen so all of them can run at once.
  # Plain Ruby, so config/viewer can use it without booting Redmine.
  module Viewers
    class Error < StandardError; end

    ROOT = File.expand_path('../../../..', __dir__)
    SCRIPT = File.expand_path('../../config/viewer', __dir__)
    INSTALL_ROOT = ENV.fetch('OBSERVABILITY_HOME') { File.join(Dir.home, '.local', 'share') }
    OS = RbConfig::CONFIG['host_os'].include?('darwin') ? 'darwin' : 'linux'
    ARCH = { 'x86_64' => 'amd64', 'aarch64' => 'arm64' }.fetch(RbConfig::CONFIG['host_cpu'], RbConfig::CONFIG['host_cpu'])

    # A release download, checked against the SHA-256 its project publishes.
    # +sums_entry+ is the line to read from a multi-file sums list, +checked+ the
    # file inside the archive that sum covers when it is not the download itself,
    # and +keep+ what is moved out of the archive into +dir+.
    Package = Struct.new(:name, :version, :url, :sums_url, :sums_entry, :checked, :keep, keyword_init: true) do
      def dir = File.join(INSTALL_ROOT, name, version)
      def path = File.join(dir, File.basename(keep || url))
    end

    # One process of a viewer; +argv+ and +env+ take the viewer's data directory.
    Service = Struct.new(:name, :argv, :env, keyword_init: true)

    # +receives+ is the URL Redmine sends spans to, in +protocol+ (:otlp or :zipkin).
    Viewer = Struct.new(:key, :label, :ui_port, :receives, :protocol, :needs, :packages, :services, :setup,
                        keyword_init: true)

    def self.github(repo, tag, file) = "https://github.com/#{repo}/releases/download/#{tag}/#{file}"

    jaeger_name = "jaeger-2.21.0-#{OS}-#{ARCH}"
    jaeger = Package.new(
      name: 'jaeger', version: '2.21.0',
      url: github('jaegertracing/jaeger', 'v2.21.0', "#{jaeger_name}.tar.gz"),
      sums_url: github('jaegertracing/jaeger', 'v2.21.0', "#{jaeger_name}.sha256sum.txt"),
      sums_entry: "#{jaeger_name}/jaeger", checked: "#{jaeger_name}/jaeger", keep: "#{jaeger_name}/jaeger"
    )

    zipkin_url = 'https://repo1.maven.org/maven2/io/zipkin/zipkin-server/3.6.1/zipkin-server-3.6.1-exec.jar'
    zipkin = Package.new(name: 'zipkin', version: '3.6.1', url: zipkin_url, sums_url: "#{zipkin_url}.sha256")

    openobserve_url = 'https://downloads.openobserve.ai/releases/openobserve/v1.0.4/' \
                      "openobserve-v1.0.4-#{OS}-#{ARCH}.tar.gz"
    openobserve = Package.new(name: 'openobserve', version: '1.0.4', url: openobserve_url,
                              sums_url: "#{openobserve_url}.sha256sum", keep: 'openobserve')

    desktop_file = "otel-desktop-viewer_#{OS}_#{ARCH}.tar.gz"
    desktop = Package.new(
      name: 'otel-desktop-viewer', version: '0.5.0',
      url: github('CtrlSpice/otel-desktop-viewer', 'v0.5.0', desktop_file),
      sums_url: github('CtrlSpice/otel-desktop-viewer', 'v0.5.0', 'checksums.txt'),
      sums_entry: desktop_file, keep: 'otel-desktop-viewer'
    )

    tempo_file = "tempo_3.1.0_#{OS}_#{ARCH}.tar.gz"
    tempo = Package.new(
      name: 'tempo', version: '3.1.0',
      url: github('grafana/tempo', 'v3.1.0', tempo_file),
      sums_url: github('grafana/tempo', 'v3.1.0', 'SHA256SUMS'), sums_entry: tempo_file, keep: 'tempo'
    )

    grafana_url = "https://dl.grafana.com/oss/release/grafana-13.2.4.#{OS}-#{ARCH}.tar.gz"
    grafana = Package.new(name: 'grafana', version: '13.2.4', url: grafana_url,
                          sums_url: "#{grafana_url}.sha256", keep: 'grafana-13.2.4')

    ALL = [
      Viewer.new(
        key: 'jaeger', label: 'Jaeger', ui_port: 16686,
        receives: 'http://localhost:4318/v1/traces', protocol: :otlp, packages: [jaeger],
        # Jaeger's built-in Zipkin receiver would otherwise take Zipkin's port 9411.
        services: [Service.new(name: 'jaeger',
                               argv: ->(_) { [jaeger.path, '--set=receivers.zipkin.endpoint=localhost:9419'] })]
      ),
      Viewer.new(
        key: 'zipkin', label: 'Zipkin', ui_port: 9411,
        receives: 'http://localhost:9411/api/v2/spans', protocol: :zipkin, needs: 'java', packages: [zipkin],
        services: [Service.new(name: 'zipkin', argv: ->(_) { ['java', '-jar', zipkin.path] },
                               env: ->(_) { { 'QUERY_PORT' => '9411' } })]
      ),
      Viewer.new(
        key: 'openobserve', label: 'OpenObserve', ui_port: 5080,
        receives: 'http://localhost:5080/api/default/v1/traces', protocol: :otlp, packages: [openobserve],
        services: [Service.new(name: 'openobserve', argv: ->(_) { [openobserve.path] },
                               env: lambda { |data|
                                 email, password = openobserve_login
                                 { 'ZO_DATA_DIR' => File.join(data, 'data'), 'ZO_HTTP_PORT' => '5080',
                                   'ZO_GRPC_PORT' => '5081', 'ZO_ROOT_USER_EMAIL' => email,
                                   'ZO_ROOT_USER_PASSWORD' => password, 'ZO_TELEMETRY' => 'false' }
                               })]
      ),
      Viewer.new(
        key: 'otel-desktop-viewer', label: 'otel-desktop-viewer', ui_port: 8000,
        receives: 'http://localhost:4328/v1/traces', protocol: :otlp, packages: [desktop],
        services: [Service.new(name: 'otel-desktop-viewer',
                               argv: lambda { |_|
                                 [desktop.path, '--browser-port', '8000', '--grpc', '4327', '--http', '4328',
                                  '--open-browser=false']
                               })]
      ),
      Viewer.new(
        key: 'grafana-tempo', label: 'Grafana Tempo', ui_port: 3300,
        receives: 'http://localhost:4338/v1/traces', protocol: :otlp, packages: [tempo, grafana],
        setup: ->(data) { write_grafana_tempo_config(data) },
        services: [
          Service.new(name: 'tempo', argv: ->(data) { [tempo.path, "-config.file=#{File.join(data, 'tempo.yaml')}"] }),
          Service.new(name: 'grafana',
                      argv: ->(_) { [File.join(grafana.path, 'bin', 'grafana'), 'server', '--homepath', grafana.path] },
                      env: lambda { |data|
                        { 'GF_SERVER_HTTP_PORT' => '3300',
                          'GF_PATHS_DATA' => File.join(data, 'grafana'),
                          'GF_PATHS_LOGS' => File.join(data, 'grafana', 'log'),
                          'GF_PATHS_PLUGINS' => File.join(data, 'grafana', 'plugins'),
                          'GF_PATHS_PROVISIONING' => File.join(data, 'provisioning'),
                          'GF_ANALYTICS_REPORTING_ENABLED' => 'false',
                          'GF_ANALYTICS_CHECK_FOR_UPDATES' => 'false' }
                      })
        ]
      )
    ].to_h { [_1.key, _1] }.freeze

    def self.data_dir(viewer) = File.join(ROOT, 'tmp', 'observability', viewer.key)
    def self.pid_file(service) = File.join(ROOT, 'tmp', 'pids', "#{service.name}.pid")
    def self.log_file(name) = File.join(ROOT, 'log', "#{name}.log")
    def self.lock_file(viewer) = File.join(ROOT, 'tmp', 'pids', "#{viewer.key}.lock")
    def self.request_file(viewer) = File.join(ROOT, 'tmp', 'pids', "#{viewer.key}.requested")

    # :running when every process is up, :starting while config/viewer holds the
    # start lock (downloads can take minutes) or was launched in the last few
    # seconds and has not taken the lock yet, otherwise :stopped.
    def self.status(viewer)
      return :running if running?(viewer)
      return :starting if File.exist?(request_file(viewer)) && File.mtime(request_file(viewer)) > Time.now - 10

      FileUtils.mkdir_p(File.dirname(lock_file(viewer)))
      File.open(lock_file(viewer), File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX | File::LOCK_NB) ? :stopped : :starting
      end
    end

    def self.running?(viewer) = viewer.services.all? { alive?(_1) }

    # Why +viewer+ cannot start here, or nil.
    def self.missing_requirement(viewer)
      return unless viewer.needs
      return if ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? { File.executable?(File.join(_1, viewer.needs)) }

      "#{viewer.label} needs #{viewer.needs} on the PATH of the Redmine process"
    end

    # Runs config/viewer detached, so a download does not hold up the request
    # and the viewer outlives Redmine restarts.
    def self.start_in_background(viewer)
      FileUtils.mkdir_p([File.join(ROOT, 'log'), File.dirname(request_file(viewer))])
      FileUtils.touch(request_file(viewer))
      spawn = lambda do
        Process.spawn(RbConfig.ruby, SCRIPT, viewer.key, 'start', in: File::NULL,
                      out: [log_file(viewer.key), 'a'], err: %i[child out], pgroup: true)
      end
      Process.detach(defined?(Bundler) ? Bundler.with_unbundled_env(&spawn) : spawn.call)
    end

    # Installs and starts +viewer+, holding its lock so concurrent starts from
    # several Redmine processes do not race. Raises Error on failure.
    def self.start(viewer, out = $stdout)
      FileUtils.mkdir_p([File.dirname(lock_file(viewer)), File.join(ROOT, 'log'), data_dir(viewer)])
      File.open(lock_file(viewer), File::RDWR | File::CREAT) do |lock|
        next out.puts("#{viewer.label} is already starting") unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        next out.puts("#{viewer.label} is already running") if running?(viewer)

        problem = missing_requirement(viewer)
        raise Error, problem if problem

        viewer.packages.each { install(_1, out) }
        viewer.setup&.call(data_dir(viewer))
        viewer.services.each { spawn_service(viewer, _1) unless alive?(_1) }
        sleep 3
        dead = viewer.services.reject { alive?(_1) }
        raise Error, "#{dead.map(&:name).join(', ')} exited at startup; see #{log_file(dead.first.name)}" if dead.any?

        out.puts "#{viewer.label} started. UI: http://localhost:#{viewer.ui_port}"
      end
    end

    def self.stop(viewer)
      FileUtils.rm_f(request_file(viewer))
      viewer.services.each do |service|
        if alive?(service)
          pid = File.read(pid_file(service)).to_i
          begin
            Process.kill('TERM', -pid)
          rescue Errno::ESRCH # not a process group leader
            Process.kill('TERM', pid)
          end
          50.times { alive?(service) ? sleep(0.2) : break }
        end
        FileUtils.rm_f(pid_file(service))
      end
    end

    def self.install(package, out = $stdout)
      return if File.exist?(package.path)

      out.puts "Downloading #{package.name} #{package.version}"
      Dir.mktmpdir('viewer') do |work|
        download = File.join(work, File.basename(package.url))
        run('curl', '-fsSL', '--retry', '3', '-o', download, package.url)
        sum = published_sum(package)
        verify(download, sum) unless package.checked
        run('tar', '-xzf', download, '-C', work) if package.keep
        verify(File.join(work, package.checked), sum) if package.checked
        FileUtils.mkdir_p(package.dir)
        FileUtils.mv(package.keep ? File.join(work, package.keep) : download, package.path)
      end
    end

    # OpenObserve creates its root user from these on first start. The password
    # is random per install and meets its rule of lower, upper, digit and symbol.
    def self.openobserve_login
      file = File.join(data_dir(ALL['openobserve']), 'login')
      unless File.exist?(file)
        password = SecureRandom.alphanumeric(20) until password&.match?(/(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "root@example.com\n#{password}-\n", perm: 0o600)
      end
      File.read(file).split("\n").first(2)
    end

    # Tempo's defaults put every path under /var/tempo, so each one is moved
    # into the data directory.
    def self.write_grafana_tempo_config(data)
      %w[datasources dashboards plugins alerting].each { FileUtils.mkdir_p(File.join(data, 'provisioning', _1)) }
      tempo = File.join(data, 'tempo')
      File.write(File.join(data, 'tempo.yaml'), <<~YAML)
        target: all
        stream_over_http_enabled: true
        server:
          http_listen_port: 3200
        distributor:
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: localhost:4337
                http:
                  endpoint: localhost:4338
        storage:
          trace:
            backend: local
            wal:
              path: #{tempo}/wal
            local:
              path: #{tempo}/blocks
        live_store:
          wal:
            path: #{tempo}/live-store/traces
          shutdown_marker_dir: #{tempo}/live-store/shutdown-marker
        block_builder:
          wal:
            path: #{tempo}/block-builder/traces
        backend_scheduler:
          local_work_path: #{tempo}/work
        usage_report:
          reporting_enabled: false
      YAML
      File.write(File.join(data, 'provisioning', 'datasources', 'tempo.yaml'), <<~YAML)
        apiVersion: 1
        datasources:
          - name: Tempo
            type: tempo
            uid: tempo
            access: proxy
            url: http://localhost:3200
            isDefault: true
            editable: false
      YAML
    end

    def self.alive?(service)
      pid = Integer(File.read(pid_file(service)), exception: false) or return false
      Process.kill(0, pid)
      true
    rescue Errno::ENOENT, Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def self.spawn_service(viewer, service)
      data = data_dir(viewer)
      env = service.env ? service.env.call(data) : {}
      pid = Process.spawn(env, 'nohup', *service.argv.call(data), chdir: data, in: File::NULL,
                          out: [log_file(service.name), 'a'], err: %i[child out], pgroup: true)
      Process.detach(pid)
      File.write(pid_file(service), pid.to_s)
    end

    def self.published_sum(package)
      text = IO.popen(['curl', '-fsSL', '--retry', '3', package.sums_url], &:read)
      raise Error, "could not download #{package.sums_url}" unless $?.success?

      line = text.lines.map(&:split).find { |_, name| package.sums_entry.nil? || name&.delete_prefix('*') == package.sums_entry }
      sum = line&.first.to_s.downcase
      raise Error, "no SHA-256 for #{package.sums_entry || package.url} in #{package.sums_url}" unless sum.match?(/\A\h{64}\z/)

      sum
    end

    def self.verify(file, sum)
      return if Digest::SHA256.file(file).hexdigest == sum

      raise Error, "SHA-256 mismatch for #{File.basename(file)}; download discarded"
    end

    def self.run(*command)
      raise Error, "#{command.first} failed: #{command.last}" unless system(*command)
    end

    private_class_method :alive?, :spawn_service, :published_sum, :verify, :run
  end
end
