# ICCR Roadmap

## Why we're using ICCR right now

We are using ICCR right now because it’s an approved docker image scanning tool by IBM.  The supported images are scratch, alpine, Ubuntu, CentOS, and RedHat. Whenever a vulnerability is found, it files a ticket which can potentially be acted upon by development. 

## Reasons why we should stay on it for now

While we aren’t able to gate pipelines on the scanning results, this currently isn’t a security requirement. All we really need to do is make sure images are scanned and if packages are out of date or base images are supported. The amount of effort to pivot to a new tool might only prove to be a sideways move at least in the short term. Thus we can wait to see if the performance issues we are seeing improve such that we can some day use them as pipeline gates. 

## Potential pivot decisions

While ICCR is sufficient for now, this might not always be the case. There are a couple upcoming events which could alter our current set of requirements. First, there is a SOC2 audit that will begin in January. If it’s determined that we need to be more proactive about Docker image scanning including adding gates on the pipelines, then the time it takes to scan the image might be prohibitive. 

Another event that count impact the future viability of ICCR is the Hamilton project. Right now, the details and requirements are still being worked out, but as early as this month (December 2019) it could be determined that the requirements for scanning could require more proactive Docker image scanning similar to what could happen with the SOC2 audit. 

All in all, the plan is to proceed, while acknowledging this could change in the coming weeks or months. 

## Potential as-is improvements

The longer we stay with ICCR, the more it might help to make one significant improvement. This is to automate stuck image reporting to the team that manages ICCR. Occasionally an image can take multiple days to scan. If it takes longer than 48 hours, the scan might be stuck. Right now it’s a manual process to check the image length and notify people on the appropriate slack channel (#registry-va-users). When really this is ripe for automation. We can create a tool that periodically checks the image scan durations and when it exceeds a specified threshold it can notify the appropriate people given their preferred notification method (email, slack, etc.).
 
