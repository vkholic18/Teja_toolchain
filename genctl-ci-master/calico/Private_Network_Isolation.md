# Private network Calico policies

<details>
 <summary><h2>(Original documentation from IKS)</h2></summary>

This set of Calico policies and host endpoints isolate the private network traffic of a cluster from other resources in the account's private network, while allowing communication on the private network that is necessary for the cluster to function. The policies target the private interface (eth0) and the pod network of a cluster.

For more information on how to use these policies, see the [IBM Cloud Kubernetes Service documentation](https://cloud.ibm.com/docs/containers?topic=containers-network_policies#isolate_workers).

> NOTE: If your worker nodes are attached to both a public and private VLAN, a public NodePort is still open on every worker node. In addition to these policies, you can also create a [Calico preDNAT network policy to block traffic to the public NodePorts](https://cloud.ibm.com/docs/containers?topic=containers-network_policies#block_ingress).

## Regions

The Calico policies are organized by region. Choose the directory for the region that your cluster is in when applying these [policies](https://github.com/IBM-Cloud/kube-samples/tree/master/calico-policies/private-network-isolation).

> NOTE: The policies in the ca-tor and eu-gb directories are meant for use with the Toronto and London locations.

## Deployment Notes

These policies specify worker node egress to `172.30.0.0/16` as the default pod subnet. If you specified a custom pod subnet when you created a classic cluster, or if you use a VPC cluster (which doesn't use the standard pod subnet by default), you must edit the `allow-all-workers-private.yaml` policy to change `172.30.0.0/16` to the pod subnet CIDR for this cluster instead. To find your cluster's pod subnet, run `ibmcloud ks cluster get -c <cluster_name_or_ID>`.

## Summary of changes made by the Calico policies

**Worker nodes**
* Egress network traffic on the private network interface for worker nodes is permitted to the following ports:
  * TCP/UDP 53 and 5353 for OpenShift version 4.3 or later for DNS
  * TCP/UDP 443 on 172.21.0.1 (or 10.10.10.1 for clusters created more than 3 years ago) for the Kubernetes master API server local proxy
  * TCP/UDP 2040 and 2041 on 172.20.0.0 for the etcd local proxy
  * Specified ports for other IBM Cloud services
* Ingress network traffic on the private network interface for worker nodes is permitted only from subnets for IBM Cloud Infrastructure to manage worker nodes through the following ports:
  * TCP/UDP 53 and 5353 for OpenShift version 4.3 or later for DNS
  * TCP/UDP 52311 for Big Fix
  * 10250 for VPN communication between the Kubernetes master and worker nodes
  * ICMP to allow infrastructure health monitoring
  * VRRP to use load balancer services

**Pods**
* Egress network traffic on the private network interface for pods to private networks is denied. If worker nodes are connected to a public VLAN, pod egress is permitted to public networks. All other pod egress on the private network interface is permitted to the following ports:
  * TCP/UDP 53 and 5353 for OpenShift version 4.3 or later for DNS
  * TCP/UDP 443 on 172.21.0.1 (or 10.10.10.1 for clusters created more than 3 years ago) for the Kubernetes master API server local proxy
  * TCP/UDP 2040 and 2041 on 172.20.0.0 for the etcd local proxy
  * TCP/UDP 20000:32767 and 443 for communication with the Kubernetes master
  * TCP 4443 for metrics-server for Kubernetes version 1.19 or later, or TCP 6443 for OpenShift version 4.3 or later
  * TCP 8443 for creating a pipeline run task
  * Specified ports for other IBM Cloud services
* Ingress network traffic on the private network interface for pods is permitted from workers in the cluster.

> **IMPORTANT**: When you apply the egress pod policies that are included in this policy set, only network traffic to the subnets and ports that are specified in the pod policies is permitted. All traffic to any subnets or ports that are not specified in the policies is blocked for all pods in all namespaces. Because only the ports and subnets that are necessary for the pods to function in IBM Cloud Kubernetes Service are specified in these policies, your pods cannot send network traffic over the private network until you add or change the Calico policy to allow them to. For example, if you use any in-cluster webhooks, you must add policies to ensure that the webhooks can make the required connections. You also must create policies for any non-local services that extend the Kubernetes API. You can find these services by running `kubectl get apiservices`. For OpenShift clusters, `default/openshift-apiserver` is included as a local service and does not require a network policy.
</details>


# Policies Applied specifically on OnePipeLine clusters
## List of Calico policies - Node Level

| Policy name                      | Order   |   Active/Inactive      | Description |
| -------------------------------- | ------- | ---------------------- | ----------- |
| `allow-ibm-ports-private`        | `1500`  |     Active             | Opens general IKS and metrics ports. |
| `allow-icmp-private`             | `1500`  |     Active             | Opens the ICMP protocol to allow infrastructure health monitoring. |
| `allow-vrrp-private`             | `1500`  |     Active             | Opens the VRRP protocol to use Kubernetes load balancer services. |
| `allow-sys-mgmt-private`         | `1800`  |     Active             | Allows egress and ingress to the IKS infrastructure private subnets. |
| `allow-private-services`         | `1900`  |     Active             | Allows workers to access other IBM Cloud services that support communication over the private network through private service endpoints. |
| `allow-all-workers-private`      | `1950`  |    Active              | Limits worker node communication on the private network to other worker nodes and pods within the cluster. |
| `log-allow-packets`              | `99890` |    Active              | Log denied packets on each worker node |
| `deny-all-private-default`       | `99900` |    Active            | Denies all other ingress to and egress from worker nodes on the private network. |
| `allow-vpc-oneplci-private`      | `1500`  |     Active             | Opens onepipelineci specific ports. |


## List of Calico policies - POD Level 

| Policy name                            | Order   |   Active/Inactive      | Description |
| -------------------------------------- | ------- | ---------------------- | ----------- |
| `allow-vpc-oneplci-pods-private`       | `1500`  |     Active             | Ports required for different toolchains created in OnePipeLine  |
| `allow-egress-kube-components-private` | `1500`  |     Active             | Ports required for master to worker node communication |
| `log-allow-packets-pods`               | `99889` |     Active             | Log denied packets on each kubernetes workload |


## Port summary table

| Policy                           | Type    | Scope | Port          | Protocol | Subnet          | Purpose
| -------------------------------- | ------- | ----- | ------------- | -------- | --------------- | -------
| `allow-egress-kube-components-private` | egress  | pod   | `53,5353`     | TCP/UDP  | *               | DNS
| `allow-egress-kube-components-private` | egress  | pod   | `443`         | TCP/UDP  | *               | Master API local proxy
| `allow-egress-kube-components-private` | egress  | pod   | `20000:32767` | TCP/UDP  | *               | Node ports
| `allow-egress-kube-components-private` | egress  | pod   | `10250`       | TCP/UDP  | *               | VPN from master to worker nodes
| `allow-egress-kube-components-private` | egress  | pod   | `2040:2041 `  | TCP/UDP  | *               | TCP/UDP 2040 and 2041 on 172.20.0.0 for the etcd local proxy
| `allow-egress-kube-components-private` | egress  | pod   | `6443`        | TCP      | *               | Sysdig
| `allow-egress-kube-components-private` | egress  | pod   | `4443`        | TCP      | *               | Metrics-server for Kubernetes
| `allow-egress-kube-components-private` | egress  | pod   | `5443`        | TCP/UDP  | *               | Egress allowed for calico apiserver
| `allow-egress-kube-components-private` | egress  | pod   | `8443`        | TCP/UDP  | *               | Egress allowed to create onepipeline run task
| `allow-vpc-onepipelineci-pods-private`       | egress  | pod   | `1194`        | TCP/UDP  | *               | sos-tools
| `allow-vpc-onepipelineci-pods-private`       | egress  | pod   | `8200`        | TCP/UDP  | *               | Vault
| `allow-vpc-onepipelineci-pods-private`       | egress  | pod   | `8834`        | TCP/UDP  | *               | sos-tools
| `allow-vpc-onepipelineci-pods-private`       | egress  | pod   | `10514`        | TCP/UDP  | *               | syslogForwarderPort
| ---------------------------            | ------  | ---   | ------------- | -------  | --------------- |
|   `deny-all`                   | both    | intf  | `*`           |          | *               | Deny-all for all namespace except kube-system,kube-public,kube-node-lease,ibm-cert-storeibm-operators,ibm-services-system, ibm-system and teleport
| ---------------------            | ------  | ---   | ------------- | -------  | ---------       |
| `allow-ibm-ports-private`        | egress  | intf  | `443`         | TCP/UDP  | *               | Master API local proxy
| `allow-ibm-ports-private`        | egress  | intf  | `514`         | TCP/UDP  | *               | LogDNA
| `allow-ibm-ports-private`        | egress  | intf  | `2040,2041`   | TCP/UDP  | 172.20.0.0/24   | etcd local proxy
| `allow-ibm-ports-private`        | egress  | intf  | `4443`        | TCP/UDP  | *               | Metrics-server for Kubernetes
| `allow-ibm-ports-private`        | egress  | intf  | `5473`        | TCP/UDP  | *               | communication to the calico-typha ClusterIP
| `allow-ibm-ports-private`        | egress  | intf  | `6443`        | TCP/UDP  | *               | Sysdig
| `allow-ibm-ports-private`        | egress  | intf  | `6514`        | TCP/UDP  | *               | LogDNA
| `allow-ibm-ports-private`        | egress  | intf  | `8834`        | TCP/UDP  | *               | SOS Tools
| `allow-ibm-ports-private`        | egress  | intf  | `20000:32767` | TCP/UDP  | *               | Node ports
| `allow-ibm-ports-private`        | both    | intf  | `53,5353`     | TCP/UDP  | *               | DNS
| `allow-ibm-ports-private`        | both    | intf  | `8834`        | TCP/UDP  | *               | Communicating with Tenable Nessus Manager 
| `allow-ibm-ports-private`        | ingress | intf  | `10250`       | TCP/UDP  | *               | VPN from master to worker nodes
| `allow-ibm-ports-private`        | ingress | intf  | `52311`       | TCP/UDP  | *               | Big Fix
| `allow-private-services`         | egress  | intf  | `80`          | TCP      | Multiple 166.9  | LogDNA
| `allow-all-workers-private`      | egress  | intf  | `*`           |          | *               | Egress to worker_private nodes
| `allow-all-workers-private`      | egress  | intf  | `*`           |          | 172.30.0.0/16   | Enables pod-to-pod across nodes
| `allow-all-workers-private`      | ingress | intf  | `*`           |          | *               | Ingress across private interface
| `allow-icmp-private`             | ingress | intf  | `*`           | ICMP     | *               | Health monitoring
| `allow-vrrp-private`             | both    | intf  | `n/a`         | VRRP     | *               | VRRP routing protocol
| `allow-sys-mgmt-private`         | both    | intf  | `*`           | TCP      | Region-specific | IKS infrastructure
| *`deny-all-private-default`*     | both    | intf  | `*`           |          | *               | Deny-all 
