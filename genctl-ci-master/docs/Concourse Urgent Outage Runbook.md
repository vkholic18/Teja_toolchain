
# Concourse Urgent Outage Runbook 

This document is for the purpose of mitigating and resolving outages relating to Concourse CI. See the Appendix section for specifics regarding the resources covered in this document.  


#### 1. Determine details, Identify & Investigate Outage(s) 

- Send out initial notification communicating that we are looking into the system running into issues.  
- Gather information about the system(s) running into issues. 
- Determine actions to take during planned outages (for external resources) 
	- Since some services send out notifications via different methods, we need to monitor email and slack.
- categorize the details and determine if when action is needed, and if so, when it is needed. After a time threshold (10 to 15 minutes), notify about the issue, and investigate. Use best judgement as to when to classify as an outage.  

#### 2. Take Actions determined 

- Send out another notification with finer details about the issue.  
	- Major outages should be posted in the the Cloudlab Workspace, in the `#cloudlab-general` channel. Minor outages should be posted in `#genctl-cicd` with an `@here`. 
	- Include the maximum time to resolve, optionally including expected time to resolve. 
		- If major unexpected issues are encountered, update the maximum time to resolve. 
	- If resource(s) causing issues are not owned by CI/CD, then provide a link to that service’s status that can be checked (if possible).  
- If there is a reasonable assumption we can stand up Concourse in another data center, and have it operate correctly, then we should stand up that instance. 
	- See the "Detailed Instructions" part of this document (below) for specific instructions.  
	- Standup process: 
		- Ensure that the webnodes and database are running 
		- Start workers 
		- Test Concourse functionality via a pipeline, being sure to test the ability to access the following services, and that they are working properly: [Link to Jira Ticket](https://jiracloud.swg.usma.ibm.com:8443/browse/CIGC-8007) for the pipeline.
			- POK workers - Ensure configuration updated to communicate with failover instance 
			- Artifactory  
			- Vault  
			- JIRA 
			- ICCR 
			- Data Center 
			- Travis
		- Set pipelines 
		- Sync Wireguard configurations (if possible) 
			- Update Wireguard documentation with new addresses. 
	- On TOR/WDC: 
		- shutdown webnodes and load balancer.
	- Setup / Check Monitoring 

### 3. Post Outage Steps 

- Send out notification that the issue is resolved 
- Create a Root Cause Analysis (RCA) 
	- Need to understand problem on technical level. In other words, we need all the information we can get, including but not limited to: 
		- what caused the issue 
		- why it caused it
		- where it caused it
		- when it was put in
		- what things in production environments it affects
		- if anything needs to be patched
	- Path to remediation
    	- Identify methods to prevent issue from reoccurring.  
		- Any additional monitoring we can add to catch the issue(s) in the future? 
		- Update documentation with any new information that has been discovered.  
			- Potentially create an informational session  
		- Create follow up tickets 
			- bugs 
			- stories 

## Detailed Instructions
This section goes into more detail regarding some of the instructions indicated above.

### Standing up an additional instance
First, you must create a VSI if one does not already exist. To do so, you need to access the IBM Cloud, and must then provision the resources from the correct location.

Note: "correct location" is dependent on what you're doing and where you want the resources to come from. If you need to do a completely clean standup, then the location will likely not be in WDC, TOR, nor FRA. 

For VSIs already setup, the applicable files may be found in 1Password.

- SSH Keys to access VSIs in TOR are under the `TOR/Cloud Infra` Vault
- the superuser password is located under the `Concourse POK/Cloud Prod` Vault, named `sudo password/user`

To connect, you would run a command like:

```
ssh -i ~/.ssh/${ssh_identity} cicd@host
```

Note that you will need the superuser password for privileged commands. 

depending on what you are setting up, the command and/or path will differ. 

```
Paths to the docker-compose file for various services:
Database: /home/cicd/postgres/docker-compose.yaml 
nginx (load balancer): /home/cicd/nginx/docker-compose.yaml
vault: /home/cicd/vault/docker-compose.yaml
Webnode: /home/cicd/concourse/docker-compose.yaml
dns-unbound: /home/cicd/unbound/docker-compose.yaml
kubernetes: /home/cicd/cc_workers/*
 - concourse.worker.configmap.cloud.yaml
 - concourse.worker.configmap.scripts.yaml
 - concourse.ns.yaml
 - concourse.worker.deployment.cloud.yaml
 - tor-iks-cluster-config.yaml

# If starting up the first time:
docker compose up ${path}

# If restarting: 
docker compose start ${path}
```

The setup for Kubernetes is different from the other services:

### Kube Master

```
# check the latest version that can be installed - 1.24 or lower - (Note: The version running in TOR is 1.23.14)
sudo apt-cache madison kubeadm

# check current version
kubectl version

# create control plane node 
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube

sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# -O flag = Download the file and save it under the original name
curl https://projectcalico.docs.tigera.io/manifests/calico.yaml -O

# Applying the yaml file creates and updates resources in a cluster
kubectl apply -f calico.yaml

watch kubectl get nodes
kubectl get pods,svc --all-namespaces

ls -l

# configures the ip tool to always use colors
ip -c a

ll
cd cc_workers/
ls -l

kubectl create --filename concourse.ns.yaml

# docker credentials needed now to do pulls - 
kubectl create secret docker-registry regcred --docker-username=causalityloop --docker-password='REDACTED' --docker-email=docker@codeloft.tech -n concourse
kubectl create --filename concourse.worker.configmap.cloud.yaml
kubectl create --filename concourse.worker.configmap.scripts.yaml
kubectl create --filename concourse.worker.deployment.cloud.yaml # Tweak IP Addresses in this file

kubectl get pods,svc --all-namespaces
kubectl get pods,svc --namespace concourse
less concourse.worker.deployment.cloud.yaml
kubectl get nodes
less concourse.worker.deployment.cloud.yaml

# For each node, label it.
kubectl label nodes tor3-k8s-w01 class=worker-cloud
# commands for labelling ... 02-24
kubectl label nodes tor3-k8s-w25 class=worker-cloud

~~~~~~~~~
# The following commands were left in for reference. 

kubectl get pods,svc --namespace concourse
vim concourse.worker.deployment.cloud.yaml
kubectl apply -f concourse.worker.deployment.cloud.yaml
kubectl get pods,svc --namespace concourse
kubectl get pods,svc --namespace concourse pod/worker-cloud-7dfb788775-5w2xj
kubectl describe --namespace concourse pod/worker-cloud-7dfb788775-5w2xj
kubectl logs --namespace concourse pod/worker-cloud-7dfb788775-5w2xj
kubectl get nodes
  
# run the kubectl drain command for all the workers (01-25 in this example) 
kubectl drain --ignore-daemonsets --delete-emptydir-data tor3-k8s-w01
# ... 02-24 ...
kubectl drain --ignore-daemonsets --delete-emptydir-data tor3-k8s-w25

kubectl get pods,svc --namespace concourse
ls
kubectl delete -f concourse.worker.deployment.cloud.yaml
kubectl get nodes  
kubectl uncordon tor3-k8s-w01
ls
vim concourse.worker.deployment.cloud.yaml
kubectl create -f concourse.worker.deployment.cloud.yaml
kubectl get pods,svc --namespace concourse
kubectl logs --namespace concourse pod/worker-cloud-7dfb788775-588dm
kubectl delete -f concourse.worker.deployment.cloud.yaml
kubectl drain --ignore-daemonsets --delete-emptydir-data tor3-k8s-w01
kubectl get pods,svc --namespace concourse
kubectl get nodes

# uncordon marks a node as schedulable
kubectl uncordon tor3-k8s-w01

kubectl apply -f concourse.worker.deployment.cloud.yaml
watch kubectl get pods,svc --namespace concourse
kubectl get pods,svc --namespace concourse
kubectl logs --namespace concourse pod/worker-cloud-7dfb788775-l7xgl
kubectl delete -f concourse.worker.deployment.cloud.yaml

# kubectl drain safely evicts all of your pods from a node
kubectl drain --ignore-daemonsets --delete-emptydir-data tor3-k8s-w01
grep cgroup /proc/filesystems
kubectl get nodes
kubectl uncordon tor3-k8s-w01
kubectl create -f concourse.worker.deployment.cloud.yaml
watch kubectl get pods,svc --namespace concourse
kubectl logs --namespace concourse pod/worker-cloud-7dfb788775-hqxdv
docker version
kubectl delete -f concourse.worker.deployment.cloud.yaml
kubectl drain --ignore-daemonsets --delete-emptydir-data tor3-k8s-w01
kubectl get nodes
kubectl uncordon tor3-k8s-w01
kubectl create -f concourse.worker.deployment.cloud.yaml
watch kubectl get pods,svc --namespace concourse
kubectl logs --namespace concourse pod/worker-cloud-7dfb788775-cqxbh
kubectl drain --ignore-daemonsets --delete-emptydir-data tor3-k8s-w02
kubectl get nodes
kubectl uncordon tor3-k8s-w02
vim concourse.worker.deployment.cloud.yaml
kubectl apply -f concourse.worker.deployment.cloud.yaml
watch kubectl get pods,svc --namespace concourse
watch kubectl get pods,svc -o wide --namespace concourse
kubectl get nodes
watch kubectl get nodes
kubectl uncordon tor3-k8s-w03
vim concourse.worker.deployment.cloud.yaml
kubectl apply -f concourse.worker.deployment.cloud.yaml
watch kubectl get nodes
kubectl uncordon tor3-k8s-w04
# uncordon w05-w24
kubectl uncordon tor3-k8s-w25
watch kubectl get nodes
vim concourse.worker.deployment.cloud.yaml
kubectl apply -f concourse.worker.deployment.cloud.yaml
watch kubectl get pods,svc -o wide --namespace concourse
ls -l
history
ls
cd cc_workers/
ll
less tor-iks-cluster-config.yaml
md5sum *
```

### Kube Worker

The created VSIs use (TODO VSI Profile details). 

Due to the amount of resources, the deployment control plane determines that it can run 2 workers per host, so choosing the same hardware profile will result in 2 workers per host. Due to restrictions when creating new VSIs, the default disk storage allocation cannot be changed, so disk storage needs to be added to the VSIs after they're created - 1 TB per worker. 2 TBs of storage need to be attached to each host. 

After the second volume has been attached, need to edit configurations to to tell the Kube and docker daemons to store all content on the data volume, rather than a directory on the boot drive. 



```
sudo kubeadm join 10.249.128.110:6443 --token REDACTED --discovery-token-ca-cert-hash REDACTED

cat /etc/docker/daemon.json
sudo vim /etc/docker/daemon.json
systemctl daemon-reload
systemctl restart docker
sudo systemctl status docker
sudo systemctl status kubelet
cat /etc/default/grub
sudo vim /etc/default/grub
sudo reboot
sudo systemctl status kubelet
sudo systemctl status docker
cat /etc/default/grub
sudo vim /etc/default/grub
sudo reboot
grep cgroup /proc/filesystems
cat /etc/default/grub
sudo reboot
less /boot/grub/grub.cfg
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo systemctl status docker
sudo systemctl status kubelet
sudo tail -f /var/log/syslog
sudo vim /etc/docker/daemon.json
systemctl daemon-reload
systemctl restart docker
sudo systemctl status docker.service
sudo journalctl -xeu docker.service
sudo vim /etc/docker/daemon.json
systemctl daemon-reload
systemctl restart docker
sudo systemctl restart kubelet
```


To start up kubernetes  - copy over to intended control plane (this folder is for getting concourse up and running - need working cluster)
```
# For each deployment yaml file, change to running deployment
kubectl create 
/home/cicd/cc_workers/*.yaml #only exists on the master node, only applied on the master node. Do not apply on worker nodes!
```


### Resolving Database Storage Issues
The Database may get filled up, causing issues to arise. 

Resolving the issue will necessitate downtime. To resolve the issue, we will need to move the database to another drive that has more space (can get to VSI through UI, add additional disk that is greater than the existing disk). We want to use at least twice the size for the new storage that will be available. After creating the new storage, we need to shut down the old database, and copy it over to the new storage. After copying the database over, we need to change the docker configuration to point to the new drive, then run docker-compose up. Another maintenance window can be scheduled to trim it down when convenient. 


### Setup Pipelines 

To setup the pipelines, it is important to first run a pipeline that tests the capabilities of the Concourse instance & confirms that it can access the resources outlined under "2. Take Actions Determined". After confirming that the resources are accessible, setting the cicd-bootstrap pipeline and running it will automatically create the pipelines. 

```
# Note that the Fly target needs to be logged into the cicd team rather than the genctl team.
fly -t ${ConcourseTarget} sp -c cicd-bootstrap.yaml -p cicd-bootstrap -l genctl-ci/params/pipeline-params.yaml
```

## Common Issues & Troubleshooting Steps:
- Filled up workers
- Anchore
- WDC Troubleshooting steps
- To login to the concourse nodes: 
  - Get IPs from https://confluence.swg.usma.ibm.com:8445/display/DevOps/Network+Information,
  - credentials from 1Password
- How to look for services? - Services will be displayed on running `docker-compose ps`. 
  - Ensure that they all report healthy. If not healthy, how to look into the docker logs for problems. 
- What are the different kinds of nodes on concourse and what role do they play? Web node, load balancer etc

### Concourse Node types
Format: [short-name -] full name: description  

- db - database: Database for Concourse workers. Stores data about pipelines.
- lb - load balancer: VSI by itself, routes web / Concourse worker traffick, routes to webnodes. 
- vault: Used to securely store secrets that are needed by Concourse in order to operate.
- web - web node: Powers the front end of Concourse / provides a UI. Talks to the workers. Handles traffic for the UI and Concourse workers
- dns-unbound - DNS
- k8s-m# - Kubernetes master
- k8s-w## - Kubernetes worker
- reg-marina - Marina registry
- reg-prod - Production registry
- vpn - Enables connections to Concourse (and SSH access to all the machines in TOR, with the correct credentials)
- mon - Zabbix Server - The Zabbix host - Stores and analyzes data sent by the Zabbix workers. Under certain conditions will identify a problem (e.g. disk space, host not responding), and may send an alert to the channel configured.

## Finalization Notes
The last step, after everything is running again, is to gain access to the VSI in question separately from the IBM Cloud CLI. You will need to access ssh credentials to do so if it has already been setup, or will need to setup ssh keys to allow remote access / outside of the IBM Cloud CLI. 

## Appendix 

### Assets: 

- Concourse 
- Zabbix Monitoring
	- VPN, Zabbix Host, Load Balancer, Database, Kubernetes, Kubernetes control plane, vault, webnodes, DNS, (Registries, Anchore \[Marina, RegProd, and Anchore are going away with OnePipeline\]) 
- Mzones (IKS clusters - RIAS installed on these. IKS Clusters in different location than Mzone, located in Dallas (?) ) - Need to cover bad states for IKS Clusters, etc. - There is a demo on how to work with the clusters. On the demos page. https://confluence.swg.usma.ibm.com:8445/display/DevOps/Demo+Recordings (Mzone debugging, IKS / Genctl Clusters)  
- Reinstate Mzones - automatic process after making PR to add Mzone back into pool 
- Vault*

*Depends on Vault instance

Assets Location(s): 

- WDC (Washington DC) 
- TOR (Toronto) 
- FRA (Frankfurt) 
- DAL (Dallas) - Mzones 

Assets not covered in this document (out of context, not owned by CI/CD):  

- Travis 
- OnePipeline 
- GitHub 
- Artifactory 

Documentation: 

https://confluence.swg.usma.ibm.com:8445/pages/viewpage.action?spaceKey=DevOps&title=Network+Information 

https://confluence.swg.usma.ibm.com:8445/display/DevOps/Demo+Recordings 

