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
require 'csv'
require 'erb'
require 'logger'
require 'pstore'

options = {}
using_ssl_connection = false
REPORTS = %w(user-reports group-reports)
REPORT_ALIASES = { 'ur' => 'user-reports', 'gr' => 'group-reports' }
REPORT_FORMATS = %w(html json csv)
LOGLEVELS = %w(debug info warning error fatal unknown)
SORT_MODE = %w(name id)
output = ''

# Performs PuppetDB interactions and returns json objects
class PdbConnection
  # Minimal configuration assumes puppetmaster localhost deployment
  # Advanced configuration supports remote execution with proper SSL certs
  def initialize(base_url = 'http://localhost:8080/pdb/query/v4',
                 using_ssl_connection = false,
                 client_cert = nil, client_key = nil, ca_cert = nil)
    @base_url = base_url
    @using_ssl_connection = using_ssl_connection

    @client_cert_file = client_cert
    @client_key_file = client_key
    @client_cert = client_cert.nil? ? nil : OpenSSL::X509::Certificate.new(File.read(client_cert))
    @client_key = client_key.nil? ? nil : OpenSSL::PKey::RSA.new(File.read(client_key))
    @ca_cert = ca_cert.nil? ? nil : ca_cert
  end

  # Provides execution of REST query
  def request(pdb_endpoint, query)
    rest_client = RestClient::Request
    # Build puppet query URL
    # Also sanitizes query string for you so it can be provided in human readable formats
    url = @base_url + pdb_endpoint + '?' + URI.encode_www_form('query' => query)
    response = nil
    $logger.debug("URL: #{URI.unescape(url)}")
    $logger.debug("Client Cert: \n#{@client_cert_file}")
    $logger.debug("Client Key: \n#{@client_key_file}")
    $logger.debug("CA Cert: \n#{@ca_cert}")
    $logger.debug("Using SSL: #{@using_ssl_connection.to_s}")
    if @using_ssl_connection
      $logger.debug("Manual Query: curl -X GET -H 'Content-Type:application/json' '#{@base_url + pdb_endpoint}' --data-urlencode '#{query}' --tlsv1 --cacert #{@ca_cert} --cert #{@client_cert_file} --key #{@client_key_file}")
    else
      $logger.debug("Manual Query: curl -X GET -H 'Content-Type:application/json' '#{@base_url + pdb_endpoint}' --data-urlencode '#{query}'")
    end
    
    begin
    if @using_ssl_connection
      response = rest_client.execute(method: :get, url: url, headers: { accept: '*/*' },
                                     ssl_client_cert: @client_cert,
                                     ssl_client_key: @client_key,
                                     ssl_ca_file: @ca_cert)
    else
      response = rest_client.execute(method: :get, url: url, headers: { accept: '*/*' })
    end
    # Handle bad queries or unknown exceptions because they are highly likely here
  rescue RestClient::InternalServerError => e
    puts e.inspect
    puts 'Query URL:' + URI.unescape(url)
    Kernel.abort('Communication error occurred')
  rescue => e
    puts e
    puts 'Query URL:' + URI.unescape(url)
    Kernel.abort('An unknown error occurred')
  end

    response = JSON.parse(response)
    $logger.debug("Response: #{response}")

    # Empty responses are not helpful
    fail Exception, 'Empty response returned' if response.empty? || response.nil?

    response
  end
end

# Container class for user account data
class UserAccounts
  attr_accessor :accounts
  include Enumerable

  def initialize
    @accounts = []
  end

  def each(&block)
    @accounts.each(&block)
  end

  # User account data returned from the accountfacts_users puppet custom structured fact
  class UserAccount
    attr_accessor :uid, :primary_gid, :uname, :shell, :home_dir, :description, :source_node
    def to_hash
      out = { 'uid' => @uid,
              'primary_gid' => @primary_gid,
              'uname' => @uname,
              'shell' => @shell,
              'source_node' => @source_node,
              'home_dir' => @home_dir,
              'description' => @description }
      out
    end
  end

  # Populate @accounts from query response
  def load_from_response(response)
    all_source_node_names = response.map { |a| a['certname'] }.uniq

    all_source_node_names.each_with_index do |node_name,node_name_index|
      $logger.info("Processing user input from #{node_name} (#{node_name_index} of #{all_source_node_names.size})")
      node_entries = response.select { |a| a['certname'] == node_name }
      # PuppetDB assigns accountfacts_users a unique array index which doesn't align with anything in the user itself
      # This index is what makes reassembling the user data difficult in a pure puppetdb query
      user_indexes = node_entries.map { |a| a['path'][1] }.uniq
      user_indexes.each_with_index do|user_index, user_index_index|
        user_entries = node_entries.select { |a| a['path'][1] == user_index }
        user = UserAccounts::UserAccount.new
        user.uid = user_entries.find { |a| a['path'][2] == 'uid' }['value']
        user.primary_gid = user_entries.find { |a| a['path'][2] == 'primary gid' }['value']
        user.uname = user_entries.find { |a| a['path'][2] == 'name' }['value']
        user.shell = user_entries.find { |a| a['path'][2] == 'shell' }['value']
        user.home_dir = user_entries.find { |a| a['path'][2] == 'homedir' }['value']
        user.description = user_entries.find { |a| a['path'][2] == 'description' }['value']
        user.source_node = node_name
        $logger.debug("Processed on #{node_name} (#{node_name_index} of #{all_source_node_names.size}) user name: #{user.uname} (#{user_index_index+1} of #{user_indexes.size})")
        @accounts << user
      end
    end
  end

  # Return an array of hashes which are a normalized form of @accounts
  def normalize_data(sort_mode)
    $logger.info('Normalizing user data...')
    accounts_grouped = @accounts.collect(&:to_hash).group_by do|a|
      { 'uname' => a['uname'],
        'uid' => a['uid'],
        'primary_gid' => a['primary_gid'],
        'shell' => a['shell'],
        'home_dir' => a['home_dir'] }
    end
    # group_by returns an array of (hash (parameters) to an array of hash(matches))
    # merge the differences between matches into subarrays and flatten responses
    # that way there is one record for each grouping
    out = accounts_grouped.collect do |a|
      a[0].merge('nodes' => a[1].collect { |b| b['source_node'] }.uniq.sort!).merge(
        'descriptions' => a[1].collect { |b| b['description'] }.uniq.sort!)
    end
    out.compact!
    sort_key = sort_mode == 'id' ? 'uid' : 'uname'
    out.sort! { |a, b| a[sort_key] <=> b[sort_key] }
  end

  # Some report formats can't handle normalized data and need it fully expanded with duplicates
  def denormalize_data(sort_mode)
    $logger.info('Denormalizing user data...')
    out = @accounts.collect(&:to_hash)
    sort_key = sort_mode == 'id' ? 'uid' : 'uname'
    out.sort! { |a, b| a[sort_key] <=> b[sort_key] }
  end
end

# Container class for node group data
class UserGroups
  attr_accessor :groups
  include Enumerable

  def initialize
    @groups = []
  end

  def each(&block)
    @groups.each(&block)
  end

  # Group account data returned from accountfacts_groups puppet custom structured fact
  class UserGroup
    attr_accessor :gid, :name, :members, :source_node

    def to_hash
      out = {
        'gid' => @gid,
        'name' => @name,
        'source_node' =>  @source_node,
        'members' => @members.uniq.sort!
      }
      out
    end
  end
  # Populate @groups from query response
  def load_from_response(response)
    all_source_node_names = response.map { |a| a['certname'] }.uniq

    all_source_node_names.each_with_index do |node_name,node_name_index|
      $logger.info("Processing group input from #{node_name} (#{node_name_index} of #{all_source_node_names.size})")
      node_entries = response.select { |a| a['certname'] == node_name }
      # PuppetDB assigns accountfacts_groups a unique array index which doesn't align with anything in the group itself
      # This index is what makes reassembling the group data difficult in a pure puppetdb query
      group_indexes = node_entries.map { |a| a['path'][1] }.uniq
      group_indexes.each_with_index do |group_index, group_index_index|
        group_entries = node_entries.select { |a| a['path'][1] == group_index }
        group = UserGroups::UserGroup.new
        group.gid = group_entries.find { |a| a['path'][2] == 'gid' }['value']
        group.name = group_entries.find { |a| a['path'][2] == 'name' }['value']
        members = []
        group_entries.select { |a| a['path'][2] == 'members' }.each { |a| members << a['value'] }
        group.members = members
        group.source_node = node_name
        $logger.debug("Processed on #{node_name} (#{node_name_index} of #{all_source_node_names.size}) group name: #{group.name} (#{group_index_index+1} of #{group_indexes.size})")
        @groups << group
      end
    end
  end

  # Populate @groups with additional data retrieved from accountfacts_users
  # User primary gids are not modeled in /etc/group
  def load_from_useraccounts(users)
    $logger.info("Merging in primary group memberships...")
    users.each do |user|
      result = @groups.find { |a| a.source_node == user.source_node && a.gid == user.primary_gid }
      # Append a star to the username so we can diffrentiate the primary gid from regular memberships
      result.members.push("*#{user.uname}") unless result.nil?
    end
  end

  # Provides an array of hashes representing a normalized form of the group data
  def normalize_data(sort_mode)
    $logger.info('Normalizing group data...')
    groups_grouped = @groups.collect(&:to_hash).group_by do|a|
      { 'gid' => a['gid'],
        'name' => a['name'],
        'members' => a['members'] }
    end
    out = groups_grouped.collect do |a|
      a[0].merge('nodes' => a[1].collect { |b| b['source_node'] }.uniq.sort!)
    end
    out.compact!
    out = out.group_by do |a|
      { 'gid' => a['gid'], 'name' => a['name'], 'membership' => { 'members' => a['members'], 'nodes' => a['nodes'] } }
    end
    out = out.keys
    out = out.group_by { |a| { 'gid' => a['gid'], 'name' => a['name'] } }.collect do |a|
      a[0].merge('membership' => a[1].collect { |b| b['membership'] })
    end
    sort_key = sort_mode == 'id' ? 'gid' : 'name'
    out.sort! { |a, b| a[sort_key] <=> b[sort_key] }
  end

  # Some report formats can't handle normalized data and need it fully expanded with duplicates
  def denormalize_data(sort_mode)
    $logger.info('Denormalizing group data...')
    # Since members are stored in a subarray, we have to compute the needed number of columns and populate them
    max_member_columns = @groups.max_by { |a| a.members.uniq.size }.members.uniq.size
    out = @groups.collect(&:to_hash)
    out.collect { |a| (0..[max_member_columns,a['members'].size].min - 1).collect { |b| a["Member_#{b}"] = a['members'][b] } }
    # Having expanded the members data, delete the original form since it's not needed or probably parseable meaningfully
    out.collect { |a| a.delete('members') }
    sort_key = sort_mode == 'id' ? 'gid' : 'name'
    out.sort! { |a, b| a[sort_key] <=> b[sort_key] }
  end
end

# Provides a JSON formatted report
module JsonReport
  def self.print_report(name, input)
    # Add some report metadata so you know when and by whom a report was run
    wrapped_input = { 'Report name' => name, 'Run on' => Time.now, 'Run by' => Etc.getlogin, 'Report data' => input }
    puts JSON.pretty_generate(wrapped_input)
  end
end

# Provides a CSV formatted report
module CSVReport
  def self.print_report(input)
    # No metadata is provided because the CSV format doesn't have a way model it without messing with column meanings or bloating columns
    out = CSV.generate(force_quotes: true) do |csv|
      csv << input.max_by{|a| a.keys}.keys
      input.each { |a| csv << a.values }
    end
    out
  end
end

# Provides a filtered HTML formatted report
# Use ERB to handle some of the HTML boiler plate, formatting, and javascript
class HtmlReport < ERB
  # To provide a search box in the html output I used a 3rd-party library
  module LightJavascriptTableFilter
    # Returns a copy of the licensing agreement for this code
    def self.third_party_license
      "<!--
Copyright (c) 2015 by Chris Coyier (http://codepen.io/chriscoyier/pen/tIuBL)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-->"
    end

    # Returns a the needed javascript to provide a filter for the output making searching easier
    # This is across the entire report, not a specific column
    def self.third_party_js
      "(function(document) {
  'use strict';

  var LightTableFilter = (function(Arr) {

    var _input;

    function _onInputEvent(e) {
      _input = e.target;
      var tables = document.getElementsByClassName(_input.getAttribute('data-table'));
      Arr.forEach.call(tables, function(table) {
        Arr.forEach.call(table.tBodies, function(tbody) {
          Arr.forEach.call(tbody.rows, _filter);
        });
      });
    }

    function _filter(row) {
      var text = row.textContent.toLowerCase(), val = _input.value.toLowerCase();
      row.style.display = text.indexOf(val) === -1 ? 'none' : 'table-row';
    }

    return {
      init: function() {
        var inputs = document.getElementsByClassName('light-table-filter');
        Arr.forEach.call(inputs, function(input) {
          input.oninput = _onInputEvent;
        });
      }
    };
  })(Array.prototype);

  document.addEventListener('readystatechange', function() {
    if (document.readyState === 'complete') {
      LightTableFilter.init();
    }
  });

})(document);"
    end
  end

  # Returns the HTML wrapped report contents
  # This is recursively called to handle sub-arrays, etc.
  def convert_array(arr)
    return '' if arr.nil?
    result = ''
    case arr
    when String, Fixnum then result << arr.to_s
    when NilClass then result << ''
    when Array
      case arr.first
      when String, Fixnum
        result << '<ul>'
        arr.each do |a|
          result << "<li>#{convert_array(a)}</li>" unless a.empty?
        end
        result << '</ul>'
      when NilClass then result << ''
      when Array
        result << '<ul>'
        arr.each do |a|
          result << convert_array(a)
        end
        result << '</ul>'
      when Hash
        # Change the formatting of sub-tables for easier viewing
        result << '<span class="ReportCSSChildTable ReportCSS"><table><thead><tr>'
        arr.first.keys.each { |a| result << "<td>#{convert_array(a)}</td>" }
        result << '</tr></thead><tbody>'
        arr.each do|a|
          result << '<tr>'
          a.values.each { |b| result << "<td>#{convert_array(b)}</td>" }
          result << '</tr>'
        end
        result << '</tbody></table></span>'
      else
        result << 'Unknown value!!'
      end
    else
      result << 'Unknown value!'
    end
  end

  # Provides a wrapped HTML row in the final report
  def convert_row(row_hash)
    result = ''
    row_hash.each_value do|col|
      result << '<td>'
      case col
      # Handle simple columns here, pass off more complex ones
      when String, Fixnum then result << col.to_s
      when NilClass then result << ''
      when Array then result << convert_array(col)
      else
        result << 'Unknown data type!!!'
      end
      result << '</td>'
    end
    result
  end

  # Returns the ERB template for the HTML report
  def self.template
    "
    <!DOCTYPE html><html>
    <head>
      <%= HtmlReport::LightJavascriptTableFilter.third_party_license %>
      <script type='text/javascript'><%= HtmlReport::LightJavascriptTableFilter.third_party_js %></script>
      <style type='text/css'>
      .ReportCSS {
        margin:0px;padding:0px;
        width:100%;
        box-shadow: 10px 10px 5px #888888;
      }.ReportCSS table{
          border-collapse: collapse;
              border-spacing: 0;
        width:100%;
        height:100%;
        margin:0px;padding:0px;
      }
      .ReportCSS tr:nth-child(odd){ background-color:#e2c6ff; }
      .ReportCSS tr:nth-child(even){ background-color:#ffffff; }
      .ReportCSS td{
        vertical-align:middle;
        border:1px solid #000000;
        text-align:left;
        padding:8px;
        font-size:13px;
        font-family:Arial;
        font-weight:normal;
        color:#000000;
      }
      .ReportCSS thead tr:first-child td{
        background:-o-linear-gradient(bottom, #7f00ff 5%, #3f007f 100%);
        background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #7f00ff), color-stop(1, #3f007f) );
        background:-moz-linear-gradient( center top, #7f00ff 5%, #3f007f 100% );

        background-color:#7f00ff;
        border:0px solid #000000;
        text-align:center;
        font-size:22px;
        font-family:Arial;
        font-weight:bold;
        color:#ffffff;
      }
      .ReportCSS ul{
        padding-left: 20px;
        padding-right: 20px;
        margin-top: 0px;
        margin-bottom: 0px;
      }
      .ReportCSSChildTable thead tr:first-child td{
        background:-o-linear-gradient(bottom, #3f579f 5%, #00207f 100%);
        background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #3f579f), color-stop(1, #00207f) );
        background:-moz-linear-gradient( center top, #3f579f 5%, #00207f 100% );

        padding-top: 4px;
        padding-bottom: 4px;
        padding-left: 4px;
        padding-right: 4px;
        background-color:#33d5d1;
        border:0px solid #000000;
        text-align:center;
        font-size:16px;
        font-family:Arial;
        font-weight:bold;
        color:#ffffff;
      }
      .ReportCSSChildTable tr:nth-child(odd){ background-color:#d4ebf5; }
      </style>
      <title><%= @name %></title>
    </head>
    <body>
    <center><h2><%= @name %></h2><br>Run On: <%= Time.now %><br>Run By: <%= Etc.getlogin %></center>
    <input type='search' class='light-table-filter' data-table='order-table' placeholder='Filter'>
    <span class='ReportCSS'>
    <table style='width 100%' class='order-table'>
      <thead><tr><% @input.first.keys.each do |column| %><%= '<td>'+column+'</td>' %><% end %></tr></thead>
      <tbody><% for @row in @input[0..-1] %><tr><%= convert_row(@row) %></tr><% end %></tbody>
    </table>
    </span>
    </body></html>
    "
  end

  # Create ERB instance and load template
  def initialize(name, input = {}, options = {})
    @name = name
    @input = input
    @template = options.fetch(:template, self.class.template)
    super(@template)
  end

  # Render ERB Template
  def result
    super(binding)
  end
end

# Handle CLI switches
OptionParser.new do |opts|
  opts.banner = 'Usage: accountfacts.reporting.rb [options]'

  opts.on('--url URL', 'Require the URL for your PuppetDB server') do |pdb|
    options[:pdb] = pdb
  end

  opts.on('--ssl_client_cert CLIENTCERT.PEM',
          'Optional PEM formatted SSL Client certificate for a remote connection to the PuppetDB') do |client_cert|
            options[:client_cert] = client_cert
          end

  opts.on('--ssl_client_key CLIENTKEY.PEM',
          'Optional PEM formatted SSL client certificate private key') do |client_key|
    options[:client_key] = client_key
  end

  opts.on('--ssl_ca_cert CA.PEM',
          'Optional PEM formatted SSL certificate for trusted SSL validation') do |ca_cert|
    options[:ca_cert] = ca_cert
  end

  opts.on('--filter_report PUPPETDB_QUERY_FILTER',
          'Optional PuppetDB filter query to apply. For example: ["select_fact_contents",["and",["=","name","kernel"],["=","value","Linux"]]]') do |query_filter|
    options[:query_filter] = query_filter
  end

  report_list = (REPORT_ALIASES.keys + REPORTS).join(',')
  opts.on('--report REPORT', REPORTS, REPORT_ALIASES, "Select Report Type:   (#{report_list})") do |report|
    options[:report] = report
  end

  opts.on('--report_format REPORT_FORMAT', REPORT_FORMATS, "Select Report Format:   (#{REPORT_FORMATS.join(',')})") do |report_format|
    options[:report_format] = report_format
  end

  opts.on('--sort_mode SORT_MODE', SORT_MODE, "Select Sorting Primary Key:   (#{SORT_MODE.join(',')})") do |sort_mode|
    options[:sort_mode] = sort_mode
  end
  
  opts.on('--loglevel LOGLEVEL', LOGLEVELS, "Select Loglevel (default warn):   (#{LOGLEVELS.join(',')})") do |loglevel|
    options[:loglevel] = loglevel
  end
  
  opts.on('--use_cache', "Enables the reuse of the last puppet query.  Useful for multiple format requirements or debugging.") do |use_cache|
    options[:use_cache] = use_cache
  end

  opts.on('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end.parse!

# Provide some basic assertion checking on input
if options[:pdb].nil?
  fail OptionParser::MissingArgument, 'No URL parameter provided'
end

unless options[:client_cert].nil? && options[:client_key].nil? && options[:ca_cert].nil?
  using_ssl_connection = true

  if options[:client_cert].nil? || options[:client_key].nil? || options[:ca_cert].nil?
    fail OptionParser::MissingArgument, 'If using SSL, all 3 SSL parameters must be provided'
  end

  fail ArgumentError, "File must be PEM formatted: #{options[:client_cert]}" unless options[:client_cert].end_with?('.pem')
  fail ArgumentError, "File must be PEM formatted: #{options[:client_key]}" unless options[:client_key].end_with?('.pem')
  fail ArgumentError, "File must be PEM formatted: #{options[:ca_cert]}" unless options[:ca_cert].end_with?('.pem')

  fail ArgumentError, "File not found: #{options[:client_cert]}" unless File.file?(options[:client_cert])
  fail ArgumentError, "File not found: #{options[:client_key]}" unless File.file?(options[:client_key])
  fail ArgumentError, "File not found: #{options[:ca_cert]}" unless File.file?(options[:ca_cert])
end

$logger = Logger.new(STDERR)
case options[:loglevel]
when 'debug'
  $logger.level = Logger::DEBUG
when 'info'
  $logger.level = Logger::INFO
when 'warn', NilClass
  $logger.level = Logger::WARN
when 'error'
  $logger.level = Logger::ERROR
when 'fatal'
  $logger.level = Logger::FATAL
when 'unknown'
  $logger.level = Logger::UNKNOWN
else
  fail ArgumentError, 'Invalid loglevel defined'
end

unless options[:pdb].end_with? '/pdb/query/v4/'
  options[:pdb] = options[:pdb] + '/pdb/query/v4/'
end

# If no filter is provided, use a generic catchall to not filter anything
filter = options[:query_filter].nil? ? '["select_fact_contents", ["~", "certname", ".*"]]' : options[:query_filter]

# Assemble queries
accountfacts_user_query = '["extract",["certname","path","value"],["and", ["=", "name", "accountfacts_users"], ["in", "certname", ["extract", "certname", ' + filter + ']]]]]'
accountfacts_group_query = '["extract",["certname","path","value"],["and", ["=", "name", "accountfacts_groups"], ["in", "certname", ["extract", "certname", ' + filter + ']]]]]'

user_account_facts = UserAccounts.new
group_account_facts = UserGroups.new

store = PStore.new('accountfacts.cache.pstore')
cached_user_query = store.transaction { store[:user_query] }
cached_group_query = store.transaction { store[:group_query] }
cached_users = store.transaction { store[:users] }
cached_groups = store.transaction { store[:groups] }

if !cached_users.nil? and !cached_groups.nil? and options[:use_cache]
  $logger.info("Loading cached data from previous run...")
  user_account_facts = store.transaction { store[:users] }
  group_account_facts = store.transaction { store[:groups] }
else
  if options[:use_cache]
    $logger.warn('Could not load existing cache data!')
  end
  # Execute queries and populate containers
  pdb_connection = PdbConnection.new(options[:pdb], using_ssl_connection, options[:client_cert], options[:client_key], options[:ca_cert])
  $logger.debug("Query filter(user): #{accountfacts_user_query}")
  $logger.debug("Query filter(group): #{accountfacts_group_query}")
  $logger.info("Requesting User Data...")
  user_account_facts.load_from_response(pdb_connection.request('fact-contents', accountfacts_user_query))
  $logger.info("Requesting Group Data...")
  group_account_facts.load_from_response(pdb_connection.request('fact-contents', accountfacts_group_query))
  $logger.info("Caching results...")
  store.transaction do
    store[:user_query] = accountfacts_user_query
    store[:group_query] = accountfacts_group_query
    store[:users] = user_account_facts
    store[:groups] = group_account_facts
  end
end

# Collect report output
case options[:report]
when 'user-reports'
  case options[:report_format]
  when 'csv' then output = CSVReport.print_report(user_account_facts.denormalize_data(options[:sort_mode]))
  when 'json' then output = JsonReport.print_report('User Account Data', user_account_facts.normalize_data(options[:sort_mode]))
  when 'html' then output = HtmlReport.new('User Account Data', user_account_facts.normalize_data(options[:sort_mode])).result
  end
when 'group-reports'
  group_account_facts.load_from_useraccounts(user_account_facts)
  case options[:report_format]
  when 'csv' then output = CSVReport.print_report(group_account_facts.denormalize_data(options[:sort_mode]))
  when 'json' then output = JsonReport.print_report('Group Data', group_account_facts.normalize_data(options[:sort_mode]))
  when 'html' then output = HtmlReport.new('Group Data', group_account_facts.normalize_data(options[:sort_mode])).result
  end
end

# Dump output to stdout so it can be redirected or piped to other locations outside the script itself
puts output
