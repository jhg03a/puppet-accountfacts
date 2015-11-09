require 'facter'
require 'etc'

Facter.add(:accountfacts_groups) do
  confine kernel: 'Linux'

  setcode do
    group_array = []

    Etc.group do |g|
      group_array.push('name' => g.name, 'gid' => g.gid, 'members' => g.mem)
    end

    group_array
  end
end
