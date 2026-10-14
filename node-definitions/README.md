# Lima node definitions

https://lima-vm.io/

<img alt="Shows a stylized 'Lima' text in bold, modern font" src="https://github.com/lima-vm/lima/raw/master/website/static/images/logo.svg" width="400" />

### networking fix (one-time action) for MacOS
https://lima-vm.io/docs/config/network/vmnet/#socket_vmnet

### create nodes
* limactl start ./lima-node-definitions/master.yaml --name master-1 --progress --yes
* for i in $(seq 1 3); do limactl start ./lima-node-definitions/worker.yaml --name worker-$1 --progress --yes; done


### shell-in and non-interactive commands
limactl shell master-1
limactl shell worker-1 -- uname -a

### commands
#### Stop all
for vm in master-1 worker-1 worker-2 worker-3; do limactl stop $vm; done

#### Start all
for vm in master-1 worker-1 worker-2 worker-3; do limactl start $vm; done

#### Nuke one
limactl stop worker-1 && limactl delete worker-1

#### Nuke all
for vm in master-1 worker-1 worker-2 worker-3; do limactl stop $vm; limactl delete $vm; done

#### List all
limactl list
