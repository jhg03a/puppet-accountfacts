require 'etc'

Facter.add(:accountfacts_groups) do
  confine :kernel do |value|
    value == "Linux"
  end
  
  setcode do
    group_array = []
    
    Etc.group { |g|
      group_array.push({"name" => g.name, "gid" => g.gid, "members" => g.mem})
    }
    
    group_array
  end
end
