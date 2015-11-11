require 'facter'
require 'etc'
require 'win32/registry'

# The ruby Etc library returns nil for windows users & groups
Facter.add(:accountfacts_users) do
  confine kernel: 'windows'

  setcode do
    user_array = []

    `net user`.split("\n")[4].split(' ').each do |u|
      sid = `wmic useraccount where name='#{u}' get sid`.split("\n")[2].strip
      homedir = ''
      Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList', Win32::Registry::KEY_READ) do |profilekey|
        if profilekey.keys.include?(sid)
          profilekey.open(sid) do |sidkey|
            homedir = sidkey['ProfileImagePath']
          end
        end
      end
      out_array = `net user #{u}`.split("\n").strip
      user_data_hash = {}
      out_array.each do |a|
        # The output assumes a 27 character wide key field
        next unless a[27] == ' '
        key = a[0..27].strip
        # This is known to be broken for group lists that extend beyond more than one or two groups
        value = a[28..-1].strip
        user_data_hash[key] = value
      end

      user_array.push(
        'name' => u,
        'description' => user_data_hash['Comment'],
        'uid' => sid,
        'primary gid' => '',
        'homedir' => homedir,
        'shell' => user_data_hash['Account active']
      )
    end
    user_array
  end
end

Facter.add(:accountfacts_groups) do
  setcode do
    group_array = []

    Etc.group do |g|
      group_array.push('name' => g.name, 'gid' => g.gid, 'members' => g.mem)
    end

    group_array
  end
end

Facter.add(:accountfacts_users) do
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
