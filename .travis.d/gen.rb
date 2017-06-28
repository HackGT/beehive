require 'yaml'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
TEMPLATES_DIR = File.join SOURCE_DIR, '../templates/'

APP_TEMPLATE = File.join TEMPLATES_DIR, 'app.yaml.erb'

# Global config for domes
domes = {}
# Keyed by dome -> app, so apps[:dev][:checkin]
apps = {}

def basename_no_ext(file)
  File.basename(file, File.extname(file))
end

# Load all the configuration files!
def load_config
  # Go through all the .yaml and .yml files here!
  (Dir['**/*.yaml'] + Dir['**/*.yml'])
    .select { |f| File.file? f }
    .select { |f| f[0] != '.' }
    .each_with_object({}) do |file, data|

    dome_name, app_name, overflow = File.split file

    if app_name.nil? || !overflow.nil?
      raise "Cannot handle more than one folder deep: #{file}"
    end
    app_name = basename_no_ext app_name

    data[dome_name] = {}
    data[dome_name][app_name] = YAML.load(File.read(file))
    data[dome_name][app_name]['name'] = app_name
    data
  end
end
