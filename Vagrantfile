ENV['VAGRANT_NO_PARALLEL'] = 'yes'

Vagrant.configure("2") do |config|

  # DNS Server
  config.vm.define "dnsserver" do |dns|
  
    dns.vm.box               = "generic/ubuntu2004"
    dns.vm.box_check_update  = false
    dns.vm.box_version       = "3.3.0"
    dns.vm.hostname          = "dnsserver"

    dns.vm.network "public_network", ip: "192.168.1.105"
    dns.vm.provision "shell", path: "setup.sh"
  end

  # Kubernetes Master Server
  config.vm.define "kmaster" do |node|
  
    node.vm.box               = "generic/ubuntu2004"
    node.vm.box_check_update  = false
    node.vm.box_version       = "3.3.0"
    node.vm.hostname          = "kmaster"

    node.vm.network "public_network", ip: "192.168.1.100"
  
    node.vm.provider :virtualbox do |v|
      v.name    = "kmaster"
      v.memory  = 4048
      v.cpus    =  2
    end
    node.vm.provision "shell", path: "setup.sh"
  
  end

  # Kubernetes Worker Nodes
  NodeCount = 2

  (1..NodeCount).each do |i|

    config.vm.define "kworker#{i}" do |node|

      node.vm.box               = "generic/ubuntu2004"
      node.vm.box_check_update  = false
      node.vm.box_version       = "3.3.0"
      node.vm.hostname          = "kworker#{i}"

      node.vm.network "public_network", ip: "192.168.1.10#{i}"

      node.vm.provider :virtualbox do |v|
        v.name    = "kworker#{i}"
        v.memory  = 4024
        v.cpus    = 1
      end
      node.vm.provision "shell", path: "setup.sh"
    end
  end
end