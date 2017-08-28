# frozen_string_literal: true
require 'kubeclient'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
KUBE_CONFIG = File.join Dir.home, '.kube/config'
KUBE_GLOB = File.join SOURCE_DIR, '../.output/kubernetes/*.yaml'
HERITAGE_TAG = 'Biodomes'

def make_client
  # configure the client
  config = Kubeclient::Config.read(KUBE_CONFIG)
  Kubeclient::Client.new(
    config.context.api_endpoint,
    config.context.api_version,
    ssl_options: config.context.ssl_options,
    auth_options: config.context.auth_options
  )
end

def kubernetes_files
  Dir[KUBE_GLOB]
    .map { |f| [YAML.safe_load(File.read(f)), f] }
end

def deployed_services(client)
  client
    .get_services
    .reject { |s| s.metadata&.labels&.heritage != HERITAGE_TAG }
end

def declared_services(files)
  files.reject do |(config, _)|
    config['metadata'] &&
      config['metadata']['labels'] &&
      config['metadata']['labels']['heritage'] == HERITAGE_TAG
  end
end

def services_to_remove(deployed, declared)
  deployed_names = Set.new deployed.map { |s| s.metadata.name }
  declared_names = Set.new declared.map { |(s, _)| s['metadata']['name'] }
  deployed_names - declared_names
end

def cleanup(dryrun: true)
  client = make_client
  kubes_files = kubernetes_files
  to_remove = services_to_remove(
    deployed_services(client),
    declared_services(kubes_files)
  )

  to_remove.each do |service|
    puts "Deleting service #{service}."
    client.delete_service service unless dryrun
  end
end

cleanup dryrun: ENV['DRYRUN'] != '1'
