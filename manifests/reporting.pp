# Installs a script which handles puppet-accountfacts reporting
class accountfacts::reporting (
  $install_path = '/opt/puppet-accountfacts',
  $user = 'root',
  $group = 'root',
){
  include stdlib
  validate_absolute_path($install_path)
  
  file { $install_path :
    mode   => '0750',
    owner  => $user,
    group  => $group,
    source => 'puppet:///modules/puppet-accountfacts/accountfacts.reporting.rb'
  }
}