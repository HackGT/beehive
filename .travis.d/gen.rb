require 'yaml'
require 'json'
require 'erb'
require 'fileutils'
require 'open-uri'
require 'securerandom'

SECRETS_URL = 'http://localhost:8001/api/v1/namespaces/kube-system'\
              '/services/kubernetes-dashboard/proxy/#!/secret'.freeze
SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
TEMPLATES_DIR = File.join SOURCE_DIR, '/templates/'
OUT_ROOT = File.join SOURCE_DIR, '../.output/'
KUBE_OUT_DIR = File.join SOURCE_DIR, '../.output/kubernetes/'
CF_OUT_DIR = File.join SOURCE_DIR, '../.output/cloudflare/'
CONFIG_ROOT = File.join SOURCE_DIR, '..'
CONFIG_YAML = File.join SOURCE_DIR, 'config.yaml'
CONFIG_ROOT_LEN = CONFIG_ROOT.split(File::SEPARATOR).length
YAML_GLOB = ['*.yaml', '*.yml'].map { |f| File.join CONFIG_ROOT, '**', f }

SERVICE_TEMPLATE = File.join TEMPLATES_DIR, 'service.yaml.erb'
DEPLOYMENT_TEMPLATE = File.join TEMPLATES_DIR, 'deployment.yaml.erb'
INGRESS_TEMPLATE = File.join TEMPLATES_DIR, 'ingress.yaml.erb'
SECRETS_TEMPLATE = File.join TEMPLATES_DIR, 'secrets.yaml.erb'
FALLBACK_SECRETS_TEMPLATE = File.join TEMPLATES_DIR, 'fallback-secrets.yaml.erb'

CONFIG = YAML.safe_load(File.read(CONFIG_YAML))

CONFIG_MAP_TEMPLATE = File.join TEMPLATES_DIR, 'configmap.yaml.erb'

POD_FILE_DIR = '/etc/files/'
MOUNT_NAME = 'files'

class IncorrectFileConfigurationError < StandardError; end

def basename_no_ext(file)
  File.basename(file, File.extname(file))
end

def make_shortname(config_name, app_name)
  (
    if config_name && app_name == :main
      config_name
    else
      app_name
    end
  ).downcase
end

def make_host(app_name, dome_name)
  if app_name == :main
    CONFIG['domain']['host']
  elsif dome_name == 'default'
    "#{app_name}.#{CONFIG['domain']['host']}"
  else
    "#{app_name}.#{dome_name}.#{CONFIG['domain']['host']}"
  end
end

def make_dockertag(branch: 'master', rev: nil)
  if !rev.nil?
    rev
  elsif branch != 'master'
    "latest-#{branch}"
  else
    'latest'
  end
end

def github_file(file, slog, branch: 'master', rev: nil)
  selector = rev.nil? ? branch : rev
  url = "https://raw.githubusercontent.com/#{slog}/#{selector}/#{file}"
  open(url).read
end

def safe_github_file(file, slog)
  github_file(file, slog)
rescue
  nil
end

def fetch_deployment(slog, branch: 'master', rev: nil)
  text = github_file('deployment.yaml', slog, branch: branch, rev: rev)
  YAML.safe_load(text)
rescue
  puts "  - No deployment.yaml found in #{slog}."
  {}
end

def parse_file_info(app_config, app_name, slog, config_path)
  files = {}
  if app_config['files'].is_a? Hash
    app_config['files'].each do |name, path|
      root = if path[0] == '/'
               CONFIG_ROOT
             else
               File.dirname config_path
             end
      local_path = File.join root, path
      contents = if File.file?(local_path)
                   File.read(local_path)
                 else
                   safe_github_file(path, slog)
                 end
      if contents
        files[name] = {
          'contents' => contents,
          'path' => path,
          'full_path' => File.join(POD_FILE_DIR, path),
          'owner' => app_name
        }
      else
        puts "  - File not found in biodomes or on GH with path: #{path}."
        raise IncorrectFileConfigurationError
      end
    end
  end
  files
end

def load_app_data(data, app_config, dome_name, app_name, path)
  # generate more configs part
  if app_config['git'].is_a? String
    remote = app_config['git']
    app_config['git'] = {}
    app_config['git']['remote'] = remote
  end
  git = app_config['git']['remote']
  branch = app_config['git']['branch'] || 'master'
  git_rev = app_config['git']['rev']
  git_rev = git_rev.downcase unless git_rev.nil?

  git_parts = git.split(File::SEPARATOR)
  repo_name = basename_no_ext(git_parts[-1])
  org_name = git_parts[-2]
  slog = "#{org_name}/#{repo_name}"

  files = parse_file_info(app_config, app_name, slog, path)

  base_config = fetch_deployment(slog, branch: branch, rev: git_rev)

  app_config = base_config.merge(app_config)

  docker_tag = make_dockertag branch: branch, rev: git_rev

  shortname = make_shortname app_config['name'], app_name

  host = make_host app_name, dome_name

  data[dome_name] = {} unless data.key? dome_name
  data[dome_name]['name'] = dome_name
  data[dome_name]['apps'] = {} unless data[dome_name].key? 'apps'
  data[dome_name]['apps'][app_name] = app_config
  data[dome_name]['apps'][app_name]['git']['slog'] = slog.downcase
  data[dome_name]['apps'][app_name]['git']['user'] = org_name.downcase
  data[dome_name]['apps'][app_name]['git']['shortname'] = repo_name.downcase
  data[dome_name]['apps'][app_name]['git']['rev'] = git_rev
  data[dome_name]['apps'][app_name]['shortname'] = shortname
  data[dome_name]['apps'][app_name]['docker-tag'] = docker_tag
  data[dome_name]['apps'][app_name]['uid'] = "#{shortname}-#{dome_name}"
  data[dome_name]['apps'][app_name]['host'] = host.downcase
  data[dome_name]['apps'][app_name]['files'] = files
  data
end

# Load all the configuration files!
def load_config
  # Go through all the .yaml and .yml files here!
  Dir[*YAML_GLOB]
    .select { |f| File.file? f }
    .reject { |f| basename_no_ext(f)[0] == '.' || f[0] == '.' }
    .map    { |f| [YAML.safe_load(File.read(f)), f] }
    .reject { |y| y[0]['ignore'] }
    .each_with_object({}) do |(app_config, file), data|

    puts "Parsing #{file}."

    components = file.split(File::SEPARATOR).drop(CONFIG_ROOT_LEN)
    dome_name, app_name = components

    if dome_name =~ /main\.ya*ml/ && app_name.nil?
      dome_name = 'default'
      app_name = :main
    elsif components.length > 2
      raise "YAML configs cannot go more than 1 directory deep! #{file}"
    elsif app_name.nil?
      app_name = basename_no_ext dome_name
      dome_name = 'default'
    else
      app_name = basename_no_ext app_name
    end

    load_app_data(data,
                  app_config,
                  dome_name.downcase,
                  app_name.downcase,
                  file)
  end
end

def write_config(path, template, bind)
  raise "File #{path} already exists! Not overwriting!" if File.exist? path
  File.open path, 'w' do |file|
    # generate the config
    data = ERB.new(File.read(template)).result(bind)
    # verify it's real YAML
    yaml = YAML.safe_load(data)
    file.write(YAML.dump(yaml))
  end
end

# Clear all our previous configuration
FileUtils.rm_rf [
  OUT_ROOT,
  KUBE_OUT_DIR,
  CF_OUT_DIR
]

# Make clean dirs
FileUtils.mkdir [
  OUT_ROOT,
  KUBE_OUT_DIR,
  CF_OUT_DIR
]

# Load all the new configurations
biodomes = load_config

# Create all the app's service and deployment conf files.
biodomes.each do |dome_name, biodome|
  biodome['mongo'] = CONFIG['mongo']['host']

  biodome['apps'].each do |app_name, app|
    unless app['files'].empty?
      path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-configmap.yaml"
      puts "Writing #{path}."
      write_config(path, CONFIG_MAP_TEMPLATE, binding)
    end

    path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-deployment.yaml"
    puts "Writing #{path}."
    write_config(path, DEPLOYMENT_TEMPLATE, binding)

    path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-service.yaml"
    puts "Writing #{path}."
    write_config(path, SERVICE_TEMPLATE, binding)

    next if app['secrets'].nil?

    path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-secrets.yaml"
    puts "Writing #{path}."
    write_config(path, SECRETS_TEMPLATE, binding)

    path = File.join KUBE_OUT_DIR, "git-#{app['git']['slog'].tr '/', '-'}" \
                                   '-secrets.yaml'

    next if File.exist? path

    puts "Writing #{path}."
    write_config(path, FALLBACK_SECRETS_TEMPLATE, binding)
  end
end

# Create the ingress.yaml file
path = File.join KUBE_OUT_DIR, 'ingress.yaml'
puts "Writing #{path}."
write_config(path, INGRESS_TEMPLATE, binding)

# Create the cloudflare DNS settings
dns = biodomes.each_with_object({}) do |(_, biodome), data|
  biodome['apps'].each_with_object(data) do |(_, app), inner_data|
    inner_data[app['host']] = {
      'type' => 'CNAME',
      'content' => CONFIG['cluster']['host'],
      'proxied' => biodome['name'] == 'default'
    }
    inner_data
  end
end

path = File.join CF_OUT_DIR, 'dns.yaml'
puts "Writing #{path}."
File.open path, 'w' do |file|
  file.write(YAML.dump(dns))
end
