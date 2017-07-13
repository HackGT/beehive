require 'yaml'
require 'json'
require 'erb'
require 'fileutils'

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

CONFIG = YAML.safe_load(File.read(CONFIG_YAML))

def basename_no_ext(file)
  File.basename(file, File.extname(file))
end

def load_app_data(data, app_config, dome_name, app_name)
  # generate more configs part
  if app_config['git'].is_a? String
    remote = app_config['git']
    app_config['git'] = {}
    app_config['git']['remote'] = remote
  end
  git = app_config['git']['remote']
  branch = app_config['git']['branch'] || 'master'
  git_parts = git.split(File::SEPARATOR)
  repo_name = basename_no_ext(git_parts[-1])
  org_name = git_parts[-2]

  # get git rev
  git_rev = app_config['git']['rev']
  if git_rev.nil?
    git_rev = `git ls-remote #{git} #{branch}`
    git_rev = git_rev.strip.split[0]
  end

  shortname = if app_config['name'] && app_name == :main
                app_config['name']
              else
                app_name
              end
  shortname.downcase!

  host = if app_name == :main
           CONFIG['domain']['host']
         elsif dome_name == 'default'
           "#{app_name}.#{CONFIG['domain']['host']}"
         else
           "#{app_name}.#{dome_name}.#{CONFIG['domain']['host']}"
         end

  data[dome_name] = {} unless data.key? dome_name
  data[dome_name]['name'] = dome_name
  data[dome_name]['apps'] = {} unless data[dome_name].key? 'apps'
  data[dome_name]['apps'][app_name] = app_config
  data[dome_name]['apps'][app_name]['git']['user'] = org_name.downcase
  data[dome_name]['apps'][app_name]['git']['shortname'] = repo_name.downcase
  data[dome_name]['apps'][app_name]['git']['rev'] = git_rev.downcase
  data[dome_name]['apps'][app_name]['shortname'] = shortname
  data[dome_name]['apps'][app_name]['uid'] = "#{shortname}-#{dome_name}"
  data[dome_name]['apps'][app_name]['host'] = host.downcase
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

    load_app_data(data, app_config, dome_name.downcase, app_name.downcase)
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
    path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-deployment.yaml"
    puts "Writing #{path}."

    File.open path, 'w' do |file|
      # generate the config
      data = ERB.new(File.read(DEPLOYMENT_TEMPLATE)).result(binding)
      # verify it's real YAML
      yaml = YAML.safe_load(data)
      file.write(YAML.dump(yaml))
    end

    path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-service.yaml"
    puts "Writing #{path}."

    File.open path, 'w' do |file|
      # generate the config
      data = ERB.new(File.read(SERVICE_TEMPLATE)).result(binding)
      # verify it's real YAML
      yaml = YAML.safe_load(data)
      file.write(YAML.dump(yaml))
    end
  end
end

# Create the ingress.yaml file
path = File.join KUBE_OUT_DIR, 'ingress.yaml'
puts "Writing #{path}."

File.open path, 'w' do |file|
  data = ERB.new(File.read(INGRESS_TEMPLATE)).result(binding)
  # verify it's real YAML
  yaml = YAML.safe_load(data)
  file.write(YAML.dump(yaml))
end

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
