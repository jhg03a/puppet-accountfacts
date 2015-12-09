# Installs a script which handles puppet-accountfacts reporting
class puppet-accountfacts::reporting (
  $install_path = '/opt/puppet-accountfacts',
  $user = 'root',
  $group = 'root'
  
  validate_absolute_path($install_path)
  
  file { $install_path :
      mode   => '0750',
      owner  => $user,
      group  => $group,
      source => "puppet:///modules/puppet-accountfacts/accountfacts.reporting.rb"
  }
)