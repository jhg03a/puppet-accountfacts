#########
# accountfacts.reporting.rb
#
# Purpose: For lack of finding a way to use puppetdb directly to perform some basic reporting, externalize it here.
#
# Author: Jonathan Gray
#
# Pre-existing requirements: A configured PuppetDB instance that supports the v4 query API that is collecting info from the puppet-accountfacts puppet module
#
#########

require 'rest-client'
require 'optparse'
require 'uri'

options = {}
using_ssl_connection = false

class PdbConnection
  def initialize(base_url = 'http://localhost:8080/pdb/query/v4')
    @base_url = base_url
    @using_ssl_connection = false
    @client_cert = nil
    @client_key = nil
    @ca_cert = nil
    @url = base_url
  end

  def initialize(base_url = 'http://localhost:8080/pdb/query/v4',
                 using_ssl_connection = false,
                 client_cert, client_key, ca_cert)
    @base_url = base_url
    @using_ssl_connection = using_ssl_connection
    @url = base_url

    @client_cert = OpenSSL::X509::Certificate.new(File.read(client_cert))
    @client_key = OpenSSL::PKey::RSA.new(File.read(client_key))
    @ca_cert = ca_cert
  end

  def request(pdb_endpoint, query)
    rest_client = RestClient::Request
    url = @base_url + pdb_endpoint + "?" + URI.encode_www_form("query" => query)
    response = nil
    if @using_ssl_connection
      response = rest_client.execute(method: :get, url: url, headers: { accept: '*/*' },
                                     ssl_client_cert: @client_cert,
                                     ssl_client_key: @client_key,
                                     ssl_ca_file: @ca_cert)
    else
      response = rest_client.execute(method: :get, url: url, headers: { accept: '*/*' })
    end
    puts response.inspect
    response
  end
end

OptionParser.new do |opts|
  opts.banner = 'Usage: accountfacts.reporting.rb [options]'

  opts.on('--url URL', 'Require the URL for your PuppetDB server') do |pdb|
    options[:pdb] = pdb
  end

  opts.on('--ssl_client_cert [CLIENTCERT.PEM]',
          'Optional PEM formatted SSL Client certificate for a remote connection to the PuppetDB') do |client_cert|
            options[:client_cert] = client_cert
          end

  opts.on('--ssl_client_key [CLIENTKEY.PEM]',
          'Optional PEM formatted SSL client certificate private key') do |client_key|
    options[:client_key] = client_key
  end

  opts.on('--ssl_ca_cert [CA.PEM]',
          'Optional PEM formatted SSL certificate for trusted SSL validation') do |ca_cert|
    options[:ca_cert] = ca_cert
  end

  opts.on('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end.parse!

p options
p ARGV

if options[:pdb].nil?
  fail OptionParser::MissingArgument, 'No URL parameter provided'
end

unless options[:client_cert].nil? && options[:client_key].nil? && options[:ca_cert].nil?
  using_ssl_connection = true

  if options[:client_cert].nil? || options[:client_key].nil? || options[:ca_cert].nil?
    fail OptionParser::MissingArgument, 'If using SSL, all 3 SSL parameters must be provided'
  end

  unless options[:client_cert].end_with?('.pem') && options[:client_key].end_with?('.pem') && options[:ca_cert].end_with?('.pem')
    fail ArgumentError, 'SSL files must be PEM formatted'
  end

  fail ArgumentError, "File not found: #{options[:client_cert]}" unless File.file?(options[:client_cert])
  fail ArgumentError, "File not found: #{options[:client_key]}" unless File.file?(options[:client_key])
  fail ArgumentError, "File not found: #{options[:ca_cert]}" unless File.file?(options[:ca_cert])
end

unless options[:pdb].end_with? '/pdb/query/v4/'
  options[:pdb] = options[:pdb] + '/pdb/query/v4/'
end

ALL_ACCOUNTFACTS_USERS_QUERY = '["=","name","accountfacts_users"]'
ALL_ACCOUNTFACTS_GROUPS_QUERY = '["=","name","accountfacts_groups"]'

pdb_connection = PdbConnection.new(options[:pdb], using_ssl_connection, options[:client_cert], options[:client_key], options[:ca_cert])
pdb_connection.request('fact-contents', ALL_ACCOUNTFACTS_USERS_QUERY)
