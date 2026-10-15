require 'digest'
require 'fileutils'
require 'rbconfig'
require 'tmpdir'

module RedmineObservability
  # The trace viewer the plugin can host on this machine, Jaeger: what to
  # download, how to run it and the ports it uses. Any other backend is
  # installed by the admin and added as a destination.
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

    # One process of a viewer; +argv+ takes the viewer's data directory.
    Service = Struct.new(:name, :argv, keyword_init: true)

    # +receives+ is the OTLP URL Redmine sends spans to.
    Viewer = Struct.new(:key, :label, :ui_port, :receives, :packages, :services, keyword_init: true)

    def self.github(repo, tag, file) = "https://github.com/#{repo}/releases/download/#{tag}/#{file}"

    jaeger_name = "jaeger-2.21.0-#{OS}-#{ARCH}"
    jaeger = Package.new(
      name: 'jaeger', version: '2.21.0',
      url: github('jaegertracing/jaeger', 'v2.21.0', "#{jaeger_name}.tar.gz"),
      sums_url: github('jaegertracing/jaeger', 'v2.21.0', "#{jaeger_name}.sha256sum.txt"),
      sums_entry: "#{jaeger_name}/jaeger", checked: "#{jaeger_name}/jaeger", keep: "#{jaeger_name}/jaeger"
    )

    ALL = [
      Viewer.new(
        key: 'jaeger', label: 'Jaeger', ui_port: 16686,
        receives: 'http://localhost:4318/v1/traces', packages: [jaeger],
        # Jaeger's built-in Zipkin receiver would otherwise take port 9411 from
        # a Zipkin the admin runs.
        services: [Service.new(name: 'jaeger',
                               argv: ->(_) { [jaeger.path, '--set=receivers.zipkin.endpoint=localhost:9419'] })]
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

        viewer.packages.each { install(_1, out) }
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
      pid = Process.spawn('nohup', *service.argv.call(data), chdir: data, in: File::NULL,
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
