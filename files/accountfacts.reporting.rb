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
require 'json'
require 'etc'
require 'erb'

options = {}
using_ssl_connection = false
REPORTS = %w(user-reports group-reports)
REPORT_ALIASES = { 'ur' => 'user-reports', 'gr' => 'group-reports' }
REPORT_FORMATS = %w(html json)

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
    url = @base_url + pdb_endpoint + '?' + URI.encode_www_form('query' => query)
    response = nil
    if @using_ssl_connection
      response = rest_client.execute(method: :get, url: url, headers: { accept: '*/*' },
                                     ssl_client_cert: @client_cert,
                                     ssl_client_key: @client_key,
                                     ssl_ca_file: @ca_cert)
    else
      response = rest_client.execute(method: :get, url: url, headers: { accept: '*/*' })
    end

    response = JSON.parse(response)

    fail Exception, 'Empty response returned' if response.empty? || response.nil?

    response
  end
end
class UserAccounts
  attr_accessor :accounts

  def initialize
    @accounts = []
  end

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

  def load_from_response(response)
    all_source_node_names = response.map { |a| a['certname'] }.uniq

    all_source_node_names.each do|node_name|
      node_entries = response.select { |a| a['certname'] == node_name }
      user_indexes = node_entries.map { |a| a['path'][1] }.uniq
      user_indexes.each do|user_index|
        user_entries = node_entries.select { |a| a['path'][1] == user_index }
        user = UserAccounts::UserAccount.new
        user.uid = user_entries.find { |a| a['path'][2] == 'uid' }['value']
        user.primary_gid = user_entries.find { |a| a['path'][2] == 'primary gid' }['value']
        user.uname = user_entries.find { |a| a['path'][2] == 'name' }['value']
        user.shell = user_entries.find { |a| a['path'][2] == 'shell' }['value']
        user.home_dir = user_entries.find { |a| a['path'][2] == 'homedir' }['value']
        user.description = user_entries.find { |a| a['path'][2] == 'description' }['value']
        user.source_node = node_name
        @accounts << user
      end
    end
  end

  def get_normalized_data
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
    end.compact.sort! { |a, b| a['uname'] <=> b['uname'] }
    out
  end
end

class UserGroups
  attr_accessor :groups

  def initialize
    @groups = []
  end

  class UserGroup
    attr_accessor :gid, :name, :members, :source_node

    def initialization
      members = []
    end
  end

  def load_from_response(response)
    all_source_node_names = response.map { |a| a['certname'] }.uniq

    all_source_node_names.each do |node_name|
      node_entries = response.select { |a| a['certname'] == node_name }
      group_indexes = node_entries.map { |a| a['path'][1] }.uniq
      group_indexes.each do |group_index|
        group_entries = node_entries.select { |a| a['path'][1] == group_index }
        group = UserGroups::UserGroup.new
        group.gid = group_entries.find { |a| a['path'][2] == 'gid' }['value']
        group.name = group_entries.find { |a| a['path'][2] == 'name' }['value']
        members = []
        group_entries.select { |a| a['path'][2] == 'members' }.each { |a| members << a['value'] }
        group.members = members
        group.source_node = node_name
        @groups << group
      end
    end
  end
end

module JsonReport
  def self.print_report(name, input)
    wrapped_input = { 'Report name' => name, 'Run on' => Time.now, 'Run by' => Etc.getlogin, 'Report data' => input }
    puts JSON.pretty_generate(wrapped_input)
  end
end

class HtmlReport < ERB
  module Light_javascript_table_filter
    def self.get_license
      "<!--
Copyright (c) 2015 by Chris Coyier (http://codepen.io/chriscoyier/pen/tIuBL)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-->"
    end

    def self.get_js
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

  def convert_row(row_hash)
    result = ''
    row_hash.each_value do|col|
      result << '<td>'
      case col
      when String, Fixnum then result << col.to_s
      when NilClass then result << ''
      when Array then
        result << '<ul>'
        col.each do |a|
          result << "<li>#{a}</li>"
        end
        result << '</ul>'
      else
        result << 'Unknown data type!!!'
      end
      result << '</td>'
    end
    result
  end

  def self.template
    "
    <!DOCTYPE html><html>
    <head>
      <%= HtmlReport::Light_javascript_table_filter.get_license %>
      <script type='text/javascript'><%= HtmlReport::Light_javascript_table_filter.get_js %></script>
      <title><%= @name %></title>
    </head>
    <body>
    <center><h2><%= @name %></h2><br>Run On: <%= Time.now %><br>Run By: <%= Etc.getlogin %></center>
    <input type='search' class='light-table-filter' data-table='order-table' placeholder='Filter'>
    <table style='width 100%' class='order-table table'>
      <tr><% for @column in @input.first.keys %><th><%= @column %></th><% end %></tr>
      <% for @row in @input[1..-1] %><tr><%= convert_row(@row) %></tr><% end %>
    </table>
    </body></html>
    "
  end

  def initialize(name, input = {}, options = {})
    @name = name
    @input = input
    @template = options.fetch(:template, self.class.template)
    super(@template)
  end

  def result
    super(binding)
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

  report_list = (REPORT_ALIASES.keys + REPORTS).join(',')
  opts.on('--report REPORT', REPORTS, REPORT_ALIASES, "Select Report Type:   (#{report_list})") do |report|
    options[:report] = report
  end

  opts.on('--report-format REPORT_FORMAT', REPORT_FORMATS, "Select Report Format:   (#{REPORT_FORMATS.join(',')})") do |report_format|
    options[:report_format] = report_format
  end

  opts.on('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end.parse!

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

unless options[:pdb].end_with? '/pdb/query/v4/'
  options[:pdb] = options[:pdb] + '/pdb/query/v4/'
end

ALL_ACCOUNTFACTS_USERS_QUERY = '["extract",["certname","path","value"],["=","name","accountfacts_users"]]'
ALL_ACCOUNTFACTS_GROUPS_QUERY = '["extract",["certname","path","value"],["=","name","accountfacts_groups"]]'

user_account_facts = UserAccounts.new
group_account_facts = UserGroups.new

pdb_connection = PdbConnection.new(options[:pdb], using_ssl_connection, options[:client_cert], options[:client_key], options[:ca_cert])
user_account_facts.load_from_response(pdb_connection.request('fact-contents', ALL_ACCOUNTFACTS_USERS_QUERY))
group_account_facts.load_from_response(pdb_connection.request('fact-contents', ALL_ACCOUNTFACTS_GROUPS_QUERY))

output = ''
case options[:report_format]
when 'json' then output = JsonReport.print_report('All User Account Data', user_account_facts.get_normalized_data)
when 'html' then output = HtmlReport.new('All User Account Data', user_account_facts.get_normalized_data).result
end
puts output
