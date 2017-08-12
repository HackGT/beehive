require 'English'
require 'kubeclient'
require 'cloudflare'
require 'base64'
require 'yaml'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
KUBE_GLOB = File.join SOURCE_DIR, '../.output/kubernetes/*.yaml'
CF_DNS_CONFIG = File.join SOURCE_DIR, '../.output/cloudflare/dns.yaml'
KUBE_CONFIG = File.join Dir.home, '.kube/config'
CONFIG_YAML = File.join SOURCE_DIR, 'config.yaml'

CONFIG = YAML.safe_load(File.read(CONFIG_YAML))

def set_cloudflare_dns
  connection = Cloudflare.connect(
    email: ENV['CLOUDFLARE_EMAIL'],
    key: ENV['CLOUDFLARE_AUTH']
  )
  zone = connection.zones.find_by_id(ENV['CLOUDFLARE_ZONE'])
  target = YAML.safe_load(File.read(CF_DNS_CONFIG))

  # update existing records
  zone.dns_records.all.each do |dns|
    next if target[dns.record[:name]].nil?
    record = target[dns.record[:name]]
    record['name'] = dns.record[:name]
    dns.put(record.to_json, content_type: 'application/json')
    puts "Changing Cloudflare DNS: #{record.to_json}"
    target.delete(dns.record[:name])
  end

  # add the remaining records
  target.each do |name, record|
    record['name'] = name
    zone.dns_records.post(record.to_json, content_type: 'application/json')
  end
end

def deploy_kubernetes
  # TODO: use ruby API?
  # configure the client
  # config = Kubeclient::Config.read(KUBE_CONFIG)
  # client = Kubeclient::Client.new(
  #   config.context.api_endpoint,
  #   config.context.api_version,
  #   ssl_options: config.context.ssl_options,
  #   auth_options: config.context.auth_options
  # )

  Dir[KUBE_GLOB]
    .map { |f| [YAML.safe_load(File.read(f)), f] }
    .each do |(config, path)|

    # create based on the kind of file
    puts "Deploying #{path}."

    # We don't want to overwrite over secrets since they are stateful.
    if config['kind'].casecmp('secret').zero?
      `kubectl describe secret #{config['metadata']['name']}`
      puts `kubectl apply -f '#{path}'` unless $CHILD_STATUS.success?
    else
      puts `kubectl apply -f '#{path}'`
    end

    raise 'kubectl exited with non-zero status.' unless $CHILD_STATUS.success?
  end
end

def install_helm_charts
  # TODO: helm
end

set_cloudflare_dns
install_helm_charts
deploy_kubernetes
