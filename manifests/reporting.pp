# Installs a script which handles puppet-accountfacts reporting
class accountfacts::reporting (
  $install_path = '/opt/puppet-accountfacts',
  $user = 'root',
  $group = 'root',
){
  include stdlib
  validate_absolute_path($install_path)
  
  if ! defined(Package['ruby']) { package { 'ruby': ensure => installed, } }
  if ! defined(Package['rubygems']) { package { 'rubygems': ensure => installed, } }
  if ! defined(Package['Rest-client']) { package { 'Rest-client': ensure => installed, provider => 'gem',} }
  
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