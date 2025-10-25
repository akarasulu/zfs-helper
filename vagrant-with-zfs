# -*- mode: ruby -*-
# vi: set ft=ruby :

repo_root = `git rev-parse --show-toplevel 2>/dev/null`.strip
raise "Unable to locate repository root" if repo_root.empty?

origin_url = `git -C "#{repo_root}" config --get remote.origin.url 2>/dev/null`.strip
raise "Unable to determine origin remote URL" if origin_url.empty?

github_match = origin_url.match(%r{\A(?:git@github\.com:|https://github\.com/)([^/]+)/(.+?)(?:\.git)?\z})
raise "Unable to parse GitHub repository from origin URL: #{origin_url}" unless github_match

owner = github_match[1]
repo_name = github_match[2]

ENV["GITHUB_REPOSITORY"] ||= "#{owner}/#{repo_name}"

repo_url = "https://#{owner}.github.io/#{repo_name}"

Vagrant.configure("2") do |config|
#  config.vm.box = "cloud-image/debian-13"
#  config.vm.box = "generic/debian12"
  config.vm.box = "brothaman/z12"

  config.vm.provision "shell", privileged: true, inline: <<-SHELL
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sudo sed -i 's|http://deb.debian.org/debian|http://ftp.tr.debian.org/debian|g' /etc/apt/sources.list

    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y 
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y socat jq

    sudo zpool create testing raidz1 /dev/vdb /dev/vdc /dev/vdd
    sudo zpool status
    sudo zpool list
    sudo mkdir /var/lib/containers
    sudo zfs create testing/var
    sudo zfs create testing/var/lib
    sudo zfs create testing/var/lib/containers
    sudo zfs create testing/var/lib/containers/privileged
    sudo zfs create testing/var/lib/containers/unprivileged
    sudo zfs set mountpoint=/var/lib/containers testing/var/lib/containers

    sudo zfs create testing/var/lib/containers/unprivileged/delegation-test
    sudo chown -R vagrant:vagrant /var/lib/containers/unprivileged/delegation-test
    sudo zfs allow vagrant \
      create,mount,mountpoint,canmount,snapshot,rollback,clone,destroy \
      testing/var/lib/containers/unprivileged/delegation-test

    if ! command -v gpg >/dev/null 2>&1; then
        echo "🔐 Installing gnupg..."
        sudo apt-get update
        sudo apt-get install -y gnupg
    fi

    echo "🔧 Adding GH-Repos APT repository..."
    REPO_URL="#{repo_url}"

    # Check if we're on a system that supports the modern method
    if [[ -d "/etc/apt/trusted.gpg.d" ]]; then
        echo "📥 Downloading and installing GPG key..."
        # Download GPG key to trusted.gpg.d (modern method)
        curl -fsSL "$REPO_URL/apt/apt-repo-pubkey.asc" | sudo tee /etc/apt/trusted.gpg.d/gh-repos.asc > /dev/null
        echo "✅ GPG key installed to /etc/apt/trusted.gpg.d/gh-repos.asc"
    else
        echo "📥 Downloading and installing GPG key (legacy method)..."
        # Fallback to apt-key for older systems
        curl -fsSL "$REPO_URL/apt/apt-repo-pubkey.asc" | sudo apt-key add -
        echo "✅ GPG key added via apt-key"
    fi

    echo "📝 Adding repository to sources..."
    # Add repository to sources
    echo "deb $REPO_URL/apt stable main" | sudo tee /etc/apt/sources.list.d/gh-repos.list

    echo "🔄 Updating package list..."
    # Update package list
    sudo apt update

    echo "📦 Installing curated packages..."
    sudo apt-get install -y zfs-helper zfs-helper-client
    echo "🎉 Repository added and packages installed!"

  SHELL

  config.vm.synced_folder ".", "/zfs-helper",
    type: "rsync",
    create: true,
    owner: 1001,
    group: 1001,
    rsync__chown: true,
    rsync__auto: false,
    rsync__args: [
      "--verbose",
      "--archive",
    ],
    rsync__exclude: [
      ".git",
      ".vagrant"
    ]

  config.vm.provider :libvirt do |libvirt|
    libvirt.memory = 4096
    libvirt.cpus   = 4

    # Extra disk #1 – 1 GB
    libvirt.storage :file,
      :size => '1G',
      :type => 'qcow2',
      :bus => 'virtio'

    # Extra disk #2 – 1 GB
    libvirt.storage :file,
      :size => '1G',
      :type => 'qcow2',
      :bus => 'virtio'

    # Extra disk #3 – 1 GB
    libvirt.storage :file,
      :size => '1G',
      :type => 'qcow2',
      :bus => 'virtio'
  end

  # Destroy disks (not removed by Vagrant libvirt provider) on 'vagrant destroy'
  config.trigger.after :destroy do |trigger|
    trigger.info = "🖴 Remove extra disk volumes ..."
    trigger.run = {
      inline: <<-'RUBY_BASH'
      bash -c '
        set -euo pipefail
        echo "🔎 Scanning for leftover libvirt volumes in pool default..."
        while read -r disk disk_path; do
          if [[ -f "${disk_path}" ]]; then
            virsh vol-delete --pool default "${disk}" || true
            echo "💥 Deleted extra disk file: ${disk_path}"
          fi
        done < <(virsh vol-list --pool default | grep 'zfs-helper_default')
      '
      RUBY_BASH
    }
  end

  config.vm.provider :vmware_desktop do |vmware|
    vmware.vmx["memsize"] = "4096"
    vmware.vmx["numvcpus"] = "4"
  end
end
