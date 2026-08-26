## Overview
This directory manages Calico Policies that needs to be created on OnePipeLine clusters.

# Default Calico and Kubernetes network policies

When a cluster with a public VLAN is created, a HostEndpoint resource with the ibm.role: worker_public label is created automatically for each worker node and its public network interface. This HostEndpoint causes all traffic to or from the public network interface to be dropped unless it is specifically allowed by a Calico policy that selects ibm.role: worker_public label.

A HostEndpoint resource with the ibm.role: worker_private label is also created automatically for each worker node and its private network interface. A default allow-all-private-default policy is created so that all traffic is allowed to and from the private network interface. This HostEndpoint makes it easy for cluster users to further restrict private network traffic by creating Calico policies that select ibm.role: worker_private and have a lower order number than the allow-all-private-default."

These default Calico host policies allow all public outbound network traffic and allow public inbound traffic to specific cluster components, such as Kubernetes NodePort, LoadBalancer, and Ingress services. All private traffic is allowed by default by the allow-all-private-default policy. Any other inbound network traffic from the internet to your worker nodes that isn't specified in the default policies gets blocked. The default policies don't affect pod to pod traffic.

## Calico Policies 
| Calico policy	      |          Description                                |
| ------------------  | --------------------------------------------------- |
| `allow-all-outbound`	| Allows all outbound traffic on the public network.|
| `allow-all-private-default` |	Allows all inbound and outbound traffic on the private network.
| `allow-bigfix-port`	   | Allows incoming traffic on port 52311 to the BigFix app to allow necessary worker node updates.|
| `allow-icmp`         | Allows incoming ICMP packets (pings).|
| `allow-node-port-dnat` |	Allows incoming network load balancer (NLB), Ingress application load balancer (ALB), and NodePort service traffic to the pods that those services are exposing. Note: You don't need to specify the exposed ports because Kubernetes uses destination network address translation (DNAT) to forward the service requests to the correct pods. That forwarding takes place before the host endpoint policies are applied in Iptables.|
| `allow-sys-mgmt`	     | Allows incoming connections for specific IBM Cloud infrastructure systems that are used to manage the worker nodes.|| 
| `allow-vrrp`	         | Allows VRRP packets, which monitor and move virtual IP addresses between worker nodes.

## Kubernetes Policies
| Kubernetes policy      |          Description                                |
| ------------------  | --------------------------------------------------- |
| `dashboard-metrics-scraper`	| Kubernetes 1.20 or later: Provided in the kube-system namespace: Blocks all pods from accessing the Kubernetes Dashboard metrics scraper. This policy doesn't prevent the Kubernetes Dashboard from accessing the dashboard metrics. Further, this policy doesn't impact accessing the dashboard metrics from the IBM Cloud console or from using kubectl proxy. If a pod requires access to the dashboard metrics scraper, deploy the pod in a namespace that has the dashboard-metrics-scraper-policy: allow label.|
| `kubernetes-dashboard` |	AProvided in the kube-system namespace: Blocks all pods from accessing the Kubernetes Dashboard. This policy doesn't impact accessing the dashboard from the IBM Cloud console or by using kubectl proxy. If a pod requires access to the dashboard, deploy the pod in a namespace that has the kubernetes-dashboard-policy: allow label.|

## Private Network Isolation
   The policies which are being applied on the OnePipeLine cluster on the private vlan can be seen in this [doc](Private_Network_Isolation.md)

## Public network Isolation
   The policies which are being applied on the OnePipeLine cluster on the public vlan can be seen in this [doc](Public_Network_Isolation.md)
 
## Calico denied packets logging 
   
   Calico packets are being logged in logdna as shown below 

   ```
    Jul 12 12:37:26 kube-cianr93w0sjo00sko3k0-tektontor01-oneplci-0000351c kern.log [852791.892864] calico-packet: IN=calif5a64ff0b11 OUT=calif5a64ff0b11 MAC=ee:ee:ee:ee:ee:ee:a6:1c:2d:c6:3d:4a:08:00 SRC=172.30.104.175 DST=172.30.104.175 LEN=60 TOS=0x00 PREC=0x00 TTL=63 ID=55435 DF PROTO=TCP SPT=57722 DPT=3000 WINDOW=65535 RES=0x00 SYN URGP=0 MARK=0x4000 
    Jul 12 12:37:38 kube-cianr93w0sjo00sko3k0-tektontor01-oneplci-0000351c syslog [852804.933184] calico-packet: IN=calif5a64ff0b11 OUT=calif5a64ff0b11 MAC=ee:ee:ee:ee:ee:ee:a6:1c:2d:c6:3d:4a:08:00 SRC=172.30.104.175 DST=172.30.104.175 LEN=60 TOS=0x00 PREC=0x00 TTL=63 ID=63868 DF PROTO=TCP SPT=47282 DPT=3000 WINDOW=65535 RES=0x00 SYN URGP=0 MARK=0x4000 
    Jul 12 12:37:38 kube-cianr93w0sjo00sko3k0-tektontor01-oneplci-0000351c syslog [852803.927820] calico-packet: IN=calif5a64ff0b11 OUT=calif5a64ff0b11 MAC=ee:ee:ee:ee:ee:ee:a6:1c:2d:c6:3d:4a:08:00 SRC=172.30.104.175 DST=172.30.104.175 LEN=60 TOS=0x00 PREC=0x00 TTL=63 ID=63867 DF PROTO=TCP SPT=47282 DPT=3000 WINDOW=65535 RES=0x00 SYN URGP=0 MARK=0x4000
   ```

   >  Here, SRC=172.30.104.175 DST=172.30.104.175 PROTO=TCP SPT=57722 DPT=3000 refere to Source from which the packet originates and destination at which the packet is being denied with the port and protocol details.
    eth=0 means the packets is traversing over the private VLAN and eth=1 means the packet is traversing over the public VLAN.

   
   The below table shows what different CIDR depict:

   | Subnet/CIDR |   Kind     |
   | ------------| ---------- |
   | 172.30.0.0/16 | Pod Subnet|
   | 172.21.0.0/16 | Service Subnet|
   | 10.X.X.X | Node  |
