# Installs a script which handles puppet-accountfacts reporting
class accountfacts::reporting (
  $install_path = '/opt/puppet-accountfacts',
  $user = 'root',
  $group = 'root',
){
  include stdlib
  validate_absolute_path($install_path)
  
  # Leaving it up to other code to manage ruby versions, gems, etc.
  # Needed rubygems: rest-client
  # Minimum ruby version > 1.9.2 (by definition of rest-client, tested with 2.0.0)
  # Consider puppet modules such as maestrodev/rvm or puppetlabs/ruby
  
  file { $install_path :
    ensure => 'directory',
    mode   => '0750',
    owner  => $user,
    group  => $group,
  }
  
  file { "${install_path}/accountfacts.reporting.rb" :
    mode   => '0750',
    owner  => $user,
    group  => $group,
    source => 'puppet:///modules/accountfacts/accountfacts.reporting.rb'
  }
}