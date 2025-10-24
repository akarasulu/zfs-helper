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
  config.vm.box = "generic/debian12"

  config.vm.provision "shell", inline: <<-SHELL
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
    sudo apt-get install -y hello-world dev-tools mock-monitor sys-info
    echo "🎉 Repository added and packages installed!"
  SHELL

  config.vm.provider :libvirt do |libvirt|
    libvirt.memory = 4096
    libvirt.cpus   = 4
  end

  config.vm.provider :vmware_desktop do |vmware|
    vmware.vmx["memsize"] = "4096"
    vmware.vmx["numvcpus"] = "4"
  end
end
