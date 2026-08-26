# One Pipeline DR Strategy
#### Overview

Protect IBM Genctl CI operations throughout a single or multi region failure by documenting the overall strategy for each scenario and its execution plan

#### FAILURE SCENARIOS

Site Failure – Single Site (LON04)

In the event of a single site failure of LON04, we will need the ability to quickly pivot to a failover site. The failover site should require minimal intervention.

TOR03, the failover site, will already contain a working Secrets Manager, IKS Cluster, and dormant toolchain deployment (dormant is defined as complete toolchain with triggers disabled)

The Secrets Manager will pre-exist, at TOR03, and will routinely be updated from the Secrets Manager at the primary site (LON04)

IKS Cluster will have nodes configured at the primary site, LON04, as well as a pool of nodes that are geolocated at TOR03. During normal operation, the workers between both clusters will service the daily operational demand. In the event of a site failure, at the primary site, we will maintain an operational build pool of 50% capacity – hosted at TOR03.

The Toolchains (and their internal dependencies) will routinely be deployed at TOR03. Besides the obvious similarities of TOR03 toolchains being identical from the primary (LON04), there will be one underlying difference. The triggers, in all respective pipelines, will be deployed as disabled. This will effectively eliminate any time penalty incurred in an infrastructure redeploy (Terraform) and reduce the time cost to a config change of a single resource (re-enable pipeline triggers).

#### Site Failure – Single Site (TOR03)

In the event of a single site failure at TOR03, the resource disruption will be isolated to the IKS cluster being used.

During normal operations, the bulk of our hosted Cloud services exist at LON04 with only IKS being geo distributed. Distributed to mean a secondary cluster located in TOR03 and not part of the same cluster at LON04. During an outage at TOR03, more specifically with IKS, ½ of the toolchains would be impacted (assuming 50/50 workload distributions of equal size/performant clusters in each geo)

The remediation path for this scenario is to reconfigure toolchains to, temporarily, pivot to use IKS (workers) at LON04 while restoration efforts at TOR03 are underway


#### Site Failure – Multi Site (LON04 and TOR03)
In the event of a multi-site failure where the primary and secondary sites (LON04/TOR03) are offline, we will need the ability to failover to a tertiary site. The tertiary site will be determined based on the available resources, at the time, and the customer impact statement.

During the primary/secondary site outage we will need to use the TaaS workers which should grant us the endpoints we need.

With the primary and secondary sites offline, there is no path that allows CI to stand up an IKS cluster at the tertiary site in a time sensitive situation. Although CI will have the ability to create/configure an IKS cluster, there is an external process/dependency from the lab team that will bridge the connection from IKS to the mzone. That process is not time sensitive and should be factored accordingly.

As a pre-requisite, there will be an off-service (IBM Cloud) backup of the Secrets Manager data that will be used to bootstrap the Secrets Manager at the tertiary site.

Resolving for IKS and Secrets Manager, the TF Toolchain code is ready to be replayed against the tertiary site and will recreate all necessary Toolchains (and their components).

#### OUT OF SCOPE

Without a large investment in time and effort, the scenario at risk is one where IBM Cloud is globally unavailable (all regions).

The builds (architecture and implementation) have a large dependency on IBM Cloud centric services that make them incompatible to readily inject into competing build platforms in the event of a global IBM Cloud failure.

Additional service outages/Toolchain dependencies not covered include:
•	Artifactory
•	Github
•	Slack
•	Image Signing (CISO)
•	Travis
•	ICCR
•	LaunchDarkly


#### EXECUTION STRATEGY

During a site failure the following playbook should be followed, based on the failure scenarios outlined below:

Site Failure – Single Site A (LON04)

•	Create new branch (can pre-exist) on devops-toolchains – ie. “failover_TOR03”
•	Recreate the IAC toolchain at TOR03
•	Update IAC toolchain to use new branch
•	Devops-toolchains repo (ideally same project/input driven to reflect failover):
o	Update TF backend and change workspace to a unique value
o	Update the region in TF
o	Update the Secrets Manager to pull from TOR03
o	Update all toolchains using LON04 workers to use TOR03
o	Update all triggers to flip “enabled”
o	Review, push, and apply changes


Site Failure – Single Site B (TOR03)

•	Devops-toolchains repo:
o	Update all toolchains using TOR03 workers to use LON04
o	Review, push, and apply changes

Site Failure – Multi Site (LON04 and TOR03)

•	Strategize on a temporary tertiary site
o	Will be referred to as site C for the following
•	Recreate the IAC toolchain at site C
•	Create new branch (can pre-exist) on devops-toolchains – ie. “failover_siteC”
•	Update IAC toolchain to use new branch
•	Manually create a Secrets Manager in site C
•	Run script (TBD) to seed a new Secrets Manager from off-line backup (ie. 1Password/other) tarball
•	Devops-toolchains repo:
o	Update TF backend and change workspace to a unique value
o	Update the region to geo of site C
o	Update the Secrets Manager to pull from site C
o	Update all toolchains using LON04/TOR03 workers to use TaaS
o	Review, push, and apply changes

#### ASSUMPTIONS
•	Secrets Manager pre-exists at TOR03
•	Secrets Manager at TOR03 is routinely updated and kept in relative sync with LON04
•	Creation of the IAC toolchain is automated (toolchain that runs against devops-toolchain repo). Ie. Is also deployed with Terraform
•	Toolchains pre-exist at TOR03 but in a disabled state (triggers are configured as disabled)
•	Offline backups of all sensitive data in Secrets Manager should be tarball’d and routinely uploaded to 1Password (in the event of failures at sites LON04/TOR03)

#### REFERENCES
•	Devops-toolchains repo
o	https://github.ibm.com/genctl-cicd/devops-toolchains
•	IAC toolchain code
o	https://github.ibm.com/genctl-cicd/genctl-ci/tree/master/onepipeline/pipelines/one_off
•	IBM TF provider	
o	Docs overview | IBM-Cloud/ibm | Terraform Registry
•	Slack channels
o	One Pipeline
o	#devops-compliance
o	TF (toolchain) provider
o	#devops-tac-users


