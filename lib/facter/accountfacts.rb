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

Facter.add(:accountfacts_users) do
  confine kernel: 'Linux'

  setcode do
    user_array = []

    Etc.passwd do |u|
      user_array.push(
        'name' => u.name,
        'description' => u.gecos,
        'uid' => u.uid,
        'primary gid' => u.gid,
        'homedir' => u.dir,
        'shell' => u.shell
      )
    end

    user_array
  end
end
