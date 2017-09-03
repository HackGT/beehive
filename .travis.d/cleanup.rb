# frozen_string_literal: true
require 'kubeclient'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
KUBE_CONFIG = File.join Dir.home, '.kube/config'
KUBE_GLOB = File.join SOURCE_DIR, '../.output/kubernetes/*.yaml'
KUBE_API_EXTENSIONS = 'extensions/v1beta1'
KUBE_API_VERSION = 'v1'
HERITAGE_TAG = 'Biodomes'

def make_client
  # configure the client
  config = Kubeclient::Config.read(KUBE_CONFIG)
  {
    classic: Kubeclient::Client.new(
      config.context.api_endpoint,
      config.context.api_version,
      ssl_options: config.context.ssl_options,
      auth_options: config.context.auth_options
    ),
    beta: Kubeclient::Client.new(
      config.context.api_endpoint + '/apis/',
      KUBE_API_EXTENSIONS,
      ssl_options: config.context.ssl_options,
      auth_options: config.context.auth_options
    )
  }
end

def kubernetes_files
  Dir[KUBE_GLOB]
    .map { |f| [YAML.safe_load(File.read(f)), f] }
end

def deployed_services(client)
  client
    .get_services
    .select { |s| s.metadata&.labels&.heritage == HERITAGE_TAG }
end

def deployed_deployments(client)
  client
    .get_deployments
    .select { |s| s.metadata&.labels&.heritage == HERITAGE_TAG }
end

def declared_services(files)
  files.select { |(config, _)| config['kind'] == 'Service' }
end

def declared_deployments(files)
  files.select { |(config, _)| config['kind'] == 'Deployment' }
end

def to_remove(deployed, declared)
  deployed_names = Set.new deployed.map { |s| s.metadata.name }
  declared_names = Set.new declared.map { |(s, _)| s['metadata']['name'] }
  deployed_names - declared_names
end

def cleanup(dryrun: true)
  client = make_client
  kubes_files = kubernetes_files

  servicies_to_remove = to_remove(
    deployed_services(client[:classic]),
    declared_services(kubes_files)
  )

  servicies_to_remove.each do |service|
    puts "Deleting service #{service}."
    puts '  - Not deleting due to dryrun.' if dryrun
    client[:classic].delete_service service, 'default' unless dryrun
  end

  deployments_to_remove = to_remove(
    deployed_deployments(client[:beta]),
    declared_deployments(kubes_files)
  )

  deployments_to_remove.each do |deployment|
    puts "Deleting deployment #{deployment}."
    puts '  - Not deleting due to dryrun.' if dryrun
    client[:beta].delete_deployment deployment, 'default' unless dryrun
  end
end

cleanup dryrun: ENV['DRYRUN'] != '0'
