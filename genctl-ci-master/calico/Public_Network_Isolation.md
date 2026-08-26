# Public network Calico policies

This set of Calico policies work in conjunction with the [default Calico policies](https://cloud.ibm.com/docs/containers?topic=containers-network_policies#default_policy) to protect public network traffic of a cluster while allowing communication on the public network that is necessary for the cluster to function. The policies target the public interface (eth1) and the pod network of a cluster.

For more information on how to use these policies, see the [IBM Cloud Kubernetes Service documentation](https://cloud.ibm.com/docs/containers?topic=containers-network_policies#isolate_workers_public).

**Tip**: In addition to these policies, you can also create a [Calico preDNAT network policy to allow or deny traffic from specific IP ranges](https://cloud.ibm.com/docs/containers?topic=containers-policy_tutorial#policy_tutorial).

<details>
 <summary><h2>(Original documentation from IKS)</h2></summary>

## Regions

The Calico policies are organized by region. Choose the directory for the region that your cluster is in when applying these [policies](https://github.com/IBM-Cloud/kube-samples/tree/master/calico-policies/public-network-isolation).

> NOTE: The policies in the ca-tor and eu-gb directories are meant for use with the Toronto and London locations.

## Deployment Notes

These policies specify worker node egress to `172.30.0.0/16` as the default pod subnet. If you specified a custom pod subnet when you created a classic cluster, or if you use a VPC cluster (which doesn't use the standard pod subnet by default), you must edit the `allow-ibm-ports-public.yaml` policy to change `172.30.0.0/16` to the pod subnet CIDR for this cluster instead. To find your cluster's pod subnet, run `ibmcloud ks cluster get -c <cluster_name_or_ID>`.

## Summary of changes made by the Calico policies

Along with the default Calico policies that are applied to the public interface of worker nodes, the Calico policies in this set configure the public network for worker node and pods as follows:

**Worker nodes**

* Egress network traffic on the public network interface for worker nodes is permitted to the following ports:
  * TCP/UDP 53 and 5353 for OpenShift version 4.3 or later for DNS
  * TCP/UDP 443 on 172.21.0.1 (or 10.10.10.1 for clusters created more than 3 years ago) for the Kubernetes master API server local proxy
  * TCP/UDP 2040 and 2041 on 172.20.0.0 for the etcd local proxy
  * Specified ports for other IBM Cloud services
* Ingress network traffic on the public network interface for worker nodes is permitted only from subnets for IBM Cloud infrastructure to manage worker nodes through the following ports:
  * TCP/UDP 53 and 5353 for OpenShift version 4.3 or later for DNS
  * TCP/UDP 52311 for Big Fix
  * ICMP to allow infrastructure health monitoring
  * VRRP to use load balancer services

> **IMPORTANT**: When you apply the egress pod policies that are included in this policy set, only network traffic to the subnets and ports that are specified in the pod policies is permitted. All traffic to any subnets or ports that are not specified in the policies is blocked for all pods in all namespaces. Because only the ports and subnets that are necessary for the pods to function in IBM Cloud Kubernetes Service are specified in these policies, your pods cannot send network traffic over the private network until you add or change the Calico policy to allow them to. For example, if you use any in-cluster webhooks, you must add policies to ensure that the webhooks can make the required connections. You also must create policies for any non-local services that extend the Kubernetes API. You can find these services by running `kubectl get apiservices`. For OpenShift clusters, `default/openshift-apiserver` is included as a local service and does not require a network policy.
</details>

## List of Calico policies

| Policy name                     | Order   | Description |
| ------------------------------- | ------- | ----------- |
| `allow-ibm-ports-public`        | `1500`  | Ports necessary for IKS worker nodes to function properly. |
| `deny-all-outbound-public`      | `1850`  | Denies all other egress from public interface. |

## Port summary table

| Policy                          | Type    | Port          | Protocol | Subnet          | Purpose
| ------------------------------- | ------- | ------------- | -------- | --------------- | -------
| `allow-ibm-ports-public`        | egress  | `443`         | TCP/UDP  | *               | Storage file systems
| `allow-ibm-ports-public`        | egress  | `5473`        | TCP/UDP  | *               | To Calico-typha ClusterIP
| `allow-ibm-ports-public`        | egress  | `6443`        | TCP/UDP  | *               | Sysdig
| `allow-ibm-ports-public`        | egress  | `20000:32767` | TCP/UDP  | *               | Node ports
| `allow-ibm-ports-public`        | egress  | `2040:2041`   | TCP/UDP  | 172.20.0.0/24   | IKS master API and etcd local proxy
| `allow-ibm-ports-public`        | egress  | `*`           | TCP/UDP  | 172.30.0.0/16   | Worker node to ClusterIP service
| `allow-ibm-ports-public`        | both    | `53`          | TCP/UDP  | *               | DNS
| `allow-ibm-ports-public`        | both    | `5353`        | TCP/UDP  | *               | DNS
| `allow-ibm-ports-public`        | both    | `8834`        | TCP/UDP  | *               | Communicating with Tenable Nessus Manager
| `allow-ibm-ports-public`        | ingress | `52311`       | TCP/UDP  | *               | Big Fix
| `deny-nodeports`                | ingress | `30000:32767` | TCP      | *               | Deny ingress on node ports
| *`deny-all-outbound-public`*    | egress  | *             | TCP/UDP  | *               | Deny rule (applied after log period)
