# Allow Tekton Workers running on IKS to connect to the deployers on qz2
 
## Why do we need this connectivity?
We need to be able to connect from the tekton workers running in IBM Cloud to the deployers (both!) in qz2 to be able to reach out genctl,
kubernetes and hostos (and RIAS IKSLess until we have a build system in NGDC). Without this connectivity we will not be able to deploy these layers.

Historically, for the analogous concourse based infrastrcuture, hosted in cloud, what we've have done is to rely on POK for this connectivity,
so instead of opening the connection from the cloud to the deployers, we opened the connection from POK to the deployers.
This approach is not good because:

- it keeps a significant dependency on POK and we want to get out of it
- does not allow infinite scalability, but we'll have to oder new hw far in advance to when we need it

The ideal, clean solution from security point of view would be to have our tekton workers running massively in the undercloud and use the ones on IKS only
to manage temporarily scaleability needs. We cannot go this way right now because we may not have sufficient hw in the undercloud for this: the current
concourse infrastructure requires several dozens of VSIs and we'll not get the equivalent in the undercloud.

If one day, we'll manage to free up some of the mzones because people would be moving to VE we may rethink moving this infrastructure in qz2.
Also, without realistic performance and scalability data on one pipeline it will be hard to assess exactly how much hw we'll need in qz2.

The risk of this approach is that we are opening a hole (for ssh protocol) from a set of IKS clusters into the deployes (for now a single cluster vs qz2 deployers). A malicious user could use this connectivity to take down all our hosts (i.e. the whole cloud).

This is why this activity must be covered by a [PCE](https://github.ibm.com/cloud-security-reviews/exceptions/blob/master/is.vpc/PCE-VPC-000936.json) .

## What do we need to do to establish this connectivity

We need to ensure we have enough secondary security controls before opening this connectivity:

- only VPC authorized personnel have access to the IBM Cloud accounts where the IKS clusters run (i.e. have a process in place to approve users
  accessing the IBM Cloud account, this is the work that needs to be done via [AccessHub](https://github.ibm.com/genctl-cicd/genctl-ci/issues/3231) )

- A subset of the individuals accessing the IBM Cloud account have access to the toolchain service instances (i.e. have a process in place to approve
  users accessing the resource group where the toolchains are, this is the work that needs to be done via [AccessHub](https://github.ibm.com/genctl-cicd/genctl-ci/issues/3231) )

- A subset of the individuals accessing the IBM Cloud account have access to the IKS clusters.
(i.e. have a process in place to approve users accessing the resource group where the toolchains are, this is the work that needs to be done via
[AccessHub](https://github.ibm.com/genctl-cicd/genctl-ci/issues/3231) )

- The clusters is managed via automation (i.e. human beings do not update it by hand, do not run kubectl commands by hand there, this is all done via automation)

- Activity Tracker is used to get the audit trail of activity on IKS clusters and toolchain instances (i.e. we must have an instance of activity tracker in
  the account and verify that every change to the toolchain or to the IKS cluster is shown in activity tracker)

- Egress rules use deny all by default and allow access from the IKS clusters to the toolchain services and to the deployers (and to all the other service
  instances that the pipeline needs to access, e.g. COS)

- A (PaaS) bastion must be put in front of the IKS clusters, see https://github.ibm.com/genctl-cicd/genctl-ci/issues/3260 . Pay attention we also need a process
  to update bastion periodically.

- csutils must be installed on the clusters, see https://github.ibm.com/genctl-cicd/genctl-ci/issues/3230 . Pay attention we also need a process to update
  csutils periodically.

- [PCE](https://github.ibm.com/cloud-security-reviews/exceptions/blob/master/is.vpc/PCE-VPC-000936.json) is updated with the info of the new account

- Network ACL are in place using the private IPs of the nodes of the clusters: if the cluster is expanded the ACL are not automatically updated, 
  see [SYS-9753](https://jiracloud.swg.usma.ibm.com:8443/browse/SYS-9753)
  
- Appropriate routing is defined on the deployers (see [SRE-8077](https://jiracloud.swg.usma.ibm.com:8443/browse/SRE-8077) ).


Since this process maybe very time consuming, it is very important we scale up the IKS cluster appropriately not to have to redo the Network ACL process
every day/week.
