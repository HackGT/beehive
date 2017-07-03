require 'kubeclient'
require 'cloudflare'
require 'base64'
require 'yaml'

# TODO: configuration options
ROOT_HOST = 'hack.gt'
CLUSTER_IP = '54.164.227.147'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
KUBE_GLOB = File.join SOURCE_DIR, '../.output/kubernetes/*.yaml'
CF_DNS_CONFIG = File.join SOURCE_DIR, '../.output/cloudflare/dns.yaml'

def set_cloudflare_dns
  connection = Cloudflare.connect(
    email: ENV['CLOUDFLARE_EMAIL'],
    key: ENV['CLOUDFLARE_AUTH']
  )
  zone = connection.zones.find_by_id(ENV['CLOUDFLARE_ZONE'])
  target = YAML.safe_load(CF_DNS_CONFIG)

  # update existing records
  zone.dns_records.all.each do |dns|
    next if target[dns.record[:name]].nil?
    record = target[dns.record[:name]]
    record['name'] = dns.record[:name]
    dns.put(record.to_json, content_type: 'application/json')
    puts 'Changing Cloudflare DNS: #{record.to_json}'
    target.delete(dns.record[:name])
  end

  # add the remaining records
  target.each do |name, record|
    record['name'] = name
    zone.dns_records.post(record.to_json, content_type: 'application/json')
  end
end

def deploy_kubernetes
  # configure the client
  kube_config = YAML.safe_load(Base64.decode64(ENV['KUBE_CONFIG']))
  config = Kubeclient::Config.new(kube_config, nil)
  client = Kubeclient::Client.new(
    config.context.api_endpoint,
    config.context.api_version,
    ssl_options: config.context.ssl_options,
    auth_options: config.context.auth_options
  )

  Dir[KUBE_GLOB]
    .map { |f| [YAML.safe_load(f), f] }
    .each do |(app, f)|

    # create based on the kind of file
    puts "Deploying #{f}."

    case app['kind'].downcase
    when 'deployment'
      client.create_deployment(app)
    when 'service'
      client.create_service(app)
    when 'ingress'
      client.create_ingress(app)
    end
  end
end

def install_helm_charts
  # TODO: helm
end

set_cloudflare_dns
install_helm_charts
deploy_kubernetes
