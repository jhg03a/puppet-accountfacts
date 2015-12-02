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
