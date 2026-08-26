# genctl-ci

This repository is used in the continuous integration effort. There is an assortment of different file types and purposes that are covered by this repository, thus this document will only go into basic details.

#### Common file types
The most common file types are generally:
 - YAML
 - Python 3 (There are some 2.x files, but only python code for 3+ should be created)
 - BASH

#### Relevant Directories
The directories that are typically the most relevant in the repo tend to be:
- pipelines (tend to be YAML files which defines the pipeline configuration)
  - templates (basic yaml templates which can be easily applied to repositories that follow a process similar to other pipelines (e.g. required files in the same places))
- scripts (tend to be BASH scripts)
- tasks (tend to be YAML files which contain bash code inline or call a script in the scripts directory)

#### Pipeline Guidelines
The following document outlines formatting to use with pipelines to keep it clear and consistent. 
[Concourse Pipeline Standards & Guidelines](https://confluence.swg.usma.ibm.com:8445/pages/viewpage.action?pageId=122225225)

#### Pipeline file creation

If you are looking at this README file in order to figure out how to get a pipeline for your repository, please read over the following document: [Repository Preparation for CICD Pipeline creation](https://confluence.swg.usma.ibm.com:8445/display/DevOps/Repository+Preparation+for+CICD+Pipeline+creation)

#### Tickets and timing
The genctl-ci team does planning for each sprint to prioritize tickets and balance time and commitments. If you know that there is something high-priority which needs to have a pipeline created quickly, it benefits you to create a ticket by following the document above, and additionally communicate the date you need it by early (preferably more than 2 weeks in advance) to the genctl-ci team, that way the ticket can be appropriately prioritized.
