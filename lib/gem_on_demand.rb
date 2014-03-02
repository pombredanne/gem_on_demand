require 'tmpdir'

module GemOnDemand
  PROJECT_CACHE = File.expand_path("~/.gem-on-demand/cache")
  DATA_CACHE = "cache"
  CACHE_DURATION = 15 * 60 # for project tags
  ProjectNotFound = Class.new(Exception)
  VERSION_REX = /^v?\d+\.\d+\.\d+(\.\w+)?$/ # with or without v and pre-release (cannot do others or we get: 'Malformed version number string 1.0.0-rails3' from bundler)
  HEAVY_FORKED = ["rails", "mysql", "mysql2"]
  MAX_VERSIONS = 50 # some projects just have a million versions ...
  DEPENDENCIES = "dependencies"
  NOT_FOUND = "not-found"
  UPDATED_AT = "updated_at"

  class << self
    def build_gem(user, project, version)
      inside_of_project(user, project) do
        cache("gem-#{version}") do
          checkout_version("v#{version}")
          gemspec = "#{project}.gemspec"
          remove_signing(gemspec)
          sh("gem build #{gemspec}")
          File.read("#{project}-#{version}.gem")
        end
      end
    end

    def dependencies(user, gems)
      (gems - HEAVY_FORKED).map do |project|
        project_dependencies(user, project)
      end.flatten
    end

    def expire(user, project)
      project = "#{PROJECT_CACHE}/#{user}/#{project}"
      return unless File.directory?(project)
      Dir.chdir project do
        expire_key UPDATED_AT
        expire_key NOT_FOUND
        expire_key DEPENDENCIES
      end
    end

    private

    def project_dependencies(user, project)
      inside_of_project(user, project) do
        cache DEPENDENCIES do
          versions_for_project.last(MAX_VERSIONS).map do |version|
            next unless dependencies = dependencies_for_version(project, version)
            {
              :name => project,
              :number => version.sub(/^v/, ""),
              :platform => "ruby",
              :dependencies => Marshal.load(dependencies)
            }
          end.compact
        end
      end
    rescue ProjectNotFound
      []
    end

    def versions_for_project
      sh("git tag").split($/).grep(VERSION_REX)
    end

    def dependencies_for_version(project, version)
      cache "dependencies-#{version}" do
        checkout_version(version)
        sh(%{ruby -e 'print Marshal.dump(eval(File.read("#{project}.gemspec")).runtime_dependencies.map{|d| [d.name, d.requirement.to_s]})'}, :fail => :allow)
      end
    end

    def cache(file, value = nil, &block)
      ensure_directory(DATA_CACHE)
      file = "#{DATA_CACHE}/#{file}"
      if block
        if File.exist?(file)
          Marshal.load(File.read(file))
        else
          result = yield
          File.write(file, Marshal.dump(result))
          result
        end
      else
        if value.nil?
          Marshal.load(File.read(file)) if File.exist?(file)
        else
          File.write(file, Marshal.dump(value))
        end
      end
    end

    def expire_key(key)
      key = "#{DATA_CACHE}/#{key}"
      File.unlink(key) if File.exist?(key)
    end

    def sh(command, options = { })
      puts command
      result = `#{command}`
      if $?.success?
        result
      elsif options[:fail] == :allow
        false
      else
        raise "Command failed: #{result}"
      end
    end

    def inside_of_project(user, project, &block)
      dir = "#{PROJECT_CACHE}/#{user}"
      ensure_directory(dir)
      Dir.chdir(dir) do
        clone_or_refresh_project(user, project)
        Dir.chdir(project, &block)
      end
    end

    def ensure_directory(dir)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end

    def clone_or_refresh_project(user, project)
      if File.directory?("#{project}/.git")
        if refresh?(project)
          Dir.chdir(project) do
            sh "git fetch origin"
            expire_key DEPENDENCIES
          end
          refreshed!(project)
        end
      elsif not_found?(project)
        raise ProjectNotFound
      else
        remove_directory(project)
        found = sh "git clone git@github.com:#{user}/#{project}.git", :fail => :allow
        if found
          refreshed!(project)
        else
          not_found!(project)
          raise ProjectNotFound
        end
      end
    end

    def remove_directory(project)
      FileUtils.rm_rf(project) if File.exist?(project)
    end

    def not_found?(project)
      File.directory?(project) && Dir.chdir(project) { cache(NOT_FOUND) }
    end

    def not_found!(project)
      ensure_directory(project)
      Dir.chdir(project) { cache(NOT_FOUND, true) }
    end

    def refreshed!(project)
      Dir.chdir(project) { cache(UPDATED_AT, Time.now.to_i) }
    end

    def refresh?(project)
      Dir.chdir(project) { cache(UPDATED_AT).to_i } < Time.now.to_i - CACHE_DURATION
    end

    def checkout_version(version)
      sh("git checkout #{version} --force")
    end

    # ERROR:  While executing gem ... (Gem::Security::Exception)
    # certificate /CN=michael/DC=grosser/DC=it not valid after 2014-02-03 18:13:11 UTC
    def remove_signing(gemspec)
      File.write(gemspec, File.read(gemspec).gsub(/.*\.(signing_key|cert_chain).*/, ""))
    end
  end
end
