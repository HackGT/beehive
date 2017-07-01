require 'yaml'
require 'erb'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
TEMPLATES_DIR = File.join SOURCE_DIR, '/templates/'

APP_TEMPLATE = File.join TEMPLATES_DIR, 'app.yaml.erb'
INGRESS_TEMPLATE = File.join TEMPLATES_DIR, 'ingress.yaml.erb'

def basename_no_ext(file)
  File.basename(file, File.extname(file))
end

# Load all the configuration files!
def load_config
  # Go through all the .yaml and .yml files here!
  (Dir['**/*.yaml'] + Dir['**/*.yml'])
    .select { |f| File.file? f }
    .select { |f| basename_no_ext(f)[0] != '.' }
    .select { |f| basename_no_ext(f)[0] != '.' }
    .each_with_object({}) do |file, data|

    puts "Parsing #{file}."

    dome_name, app_name, overflow = File.split file

    next if dome_name == 'output'

    if app_name.nil? || !overflow.nil?
      raise "Cannot handle more than one folder deep: #{file}"
    end
    app_name = basename_no_ext app_name

    app_config = YAML.safe_load(File.read(file))
    next if app_config['ignore']

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

    data[dome_name] = {} unless data.key? dome_name
    data[dome_name][app_name] = app_config
    data[dome_name][app_name]['shortname'] = app_name
    data[dome_name][app_name]['git']['user'] = org_name
    data[dome_name][app_name]['git']['shortname'] = repo_name
    data[dome_name][app_name]['git']['rev'] = git_rev
    data
  end
end

puts `rm -rf output/*.yaml`

biodomes = load_config

biodomes.each do |dome_name, apps|
  dome = {}
  dome['name'] = dome_name
  # TODO: get the real value from
  dome['mongo'] = 'mongo'

  apps.each do |app_name, app|
    path = "output/#{app_name}-#{dome_name}-deployment.yaml"
    puts "Writing #{path}."

    File.open path, 'w' do |file|
      data = ERB.new(File.read(APP_TEMPLATE)).result(binding)
      file.write(data)
    end
  end
end

path = 'output/ingress.yaml'
puts "Writing #{path}."

File.open path, 'w' do |file|
  data = ERB.new(File.read(INGRESS_TEMPLATE)).result(binding)
  file.write(data)
end
