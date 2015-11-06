require 'spec_helper'
describe 'accountfacts' do

  context 'with defaults for all parameters' do
    it { should contain_class('accountfacts') }
  end
end
