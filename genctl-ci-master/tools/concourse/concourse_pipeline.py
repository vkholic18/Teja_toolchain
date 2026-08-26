#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# /usr/local/bin/python3
"""
* This class performs parsing operations on a given concourse pipeline. The yaml can be translated to remove all
* hardcodes, which can then be written out to a new test yaml pipeline config and a separate substitutions files that
* just contains the substitution variables that were factored out
"""

###############################################################################
# I M P O R T S ###############################################################
###############################################################################

import logging
import os
import re

from ruamel.yaml import YAML
from concourse.user_exceptions import ConfigError
from concourse.git_functions import clone_and_fork_repo


###############################################################################
# C L A S S ###################################################################
###############################################################################

class ConcoursePipeline:
    """
    * This class performs parsing operations on a given concourse pipeline. The yaml can be translated to remove all
    * hardcodes, which can then be written out to a new test yaml pipeline config and a separate substitutions files that
    * just contains the substitution variables that were factored out
    """

    def __init__(self, yaml_pipeline, sandbox_dir=None, git_user=None):
        """
        * read the yaml pipeline config on init
        """
        self._yaml_file = yaml_pipeline
        self.yaml_config = None
        self.sandbox_dir = sandbox_dir

        self.git_user = git_user
        self.git_repos = list()
        self.git_forks = list()

        self.logger = logging.getLogger()

        try:
            self.validate_and_read_yaml()
        except:
            self.logger.error("There was an issue parsing the yaml: {}".format(yaml_pipeline))
            raise

    @property
    def yaml_file(self):
        """
        :return: return filename
        """
        return self._yaml_file

    @yaml_file.setter
    def yaml_file(self, value):
        """
        :return: set filename
        """
        self._yaml_file = value

    @staticmethod
    def calculate_sub_var(res_type, res_name, field):
        """
        * calculate a uniquely named sub var based on a combination of fields of the config
        *
        :param res_type: type of resource
        :param res_name: resource name
        :param field: field we are subbing for
        :return: return a uniquely names subvar
        """
        return "(({}_{}_{}))".format(res_type, res_name, field)

    def process_credential(self, resource, credential_type):
        """
        * parse either the username or password, if it exists
        *
        :param resource: a resource config
        :param credential_type: username/password field
        :return: name of the original/sub var used
        """

        original_value = ""
        sub_var_used = ""

        # parse credential if it exists
        if credential_type in resource['source']:
            self.logger.debug("{} {}: {}".format(resource['type'], credential_type, resource['source'][credential_type]))
            pattern = r"^\(\(.*\)\)$"
            if re.match(pattern, resource['source'][credential_type]):
                self.logger.debug("already using subvars: {}".format(resource['source'][credential_type]))
            else:
                sub_var_used = self.calculate_sub_var(resource['type'], resource['name'], credential_type)
                self.logger.warning("Hardcode found ({}) replacing with substitution var: {}".format(
                    resource['source'][credential_type], sub_var_used))

                original_value = resource['source'][credential_type]
                resource['source'][credential_type] = sub_var_used

        return original_value, sub_var_used

    def process_repo_or_endpoint_or_url(self, resource, repo_or_endpoint_or_url, regex=None, group=1):
        """
        * from a resource, parse a field from the source layer as either a repo, endpoint, or url
        *
        :param resource: resource config block
        :param repo_or_endpoint_or_url: field to parse
        :param regex: search criteria, none if replacing entire field in substitution
        :param group: what group from the regex are we interested in
        :return: the original/substitution variable used
        """

        original_value = ""
        sub_var_used = ""

        if repo_or_endpoint_or_url in resource['source']:
            pattern = r"^\(\(.*\)\)"
            if re.match(pattern, resource['source'][repo_or_endpoint_or_url]):
                self.logger.debug("already using subvars: {}".format(resource['source'][repo_or_endpoint_or_url]))
            else:
                # if regex is none we are just going to swap the whole thing out
                if regex is None:
                    sub_var_used = self.calculate_sub_var(resource['type'], resource['name'], repo_or_endpoint_or_url)
                    self.logger.warning("Hardcode found ({}) replacing with substitution var: {}".format(
                        resource['source'][repo_or_endpoint_or_url], sub_var_used))

                    original_value = resource['source'][repo_or_endpoint_or_url]
                    resource['source'][repo_or_endpoint_or_url] = sub_var_used
                else:
                    new_pattern = regex
                    self.logger.debug("pattern: {}".format(new_pattern))
                    self.logger.debug("search: {}".format(resource['source'][repo_or_endpoint_or_url]))
                    match_obj = re.match(new_pattern, resource['source'][repo_or_endpoint_or_url], re.I)

                    if match_obj:

                        sub_var_used = self.calculate_sub_var(resource['type'], resource['name'], repo_or_endpoint_or_url)
                        self.logger.warning("Hardcode found ({}) replacing with substitution var: {}".format(
                            resource['source'][repo_or_endpoint_or_url], sub_var_used))

                        original_value = resource['source'][repo_or_endpoint_or_url].replace(match_obj.group(group), '')
                        resource['source'][repo_or_endpoint_or_url] = sub_var_used + match_obj.group(group)
                    else:
                        self.logger.warning("We could not parse host from: {}".format(resource['source'][repo_or_endpoint_or_url]))

        return original_value, sub_var_used

    def parse_config_as_test(self, write_out_test_yamls=True):
        """
        * open the yaml file and parse it. for all hardcodes found, replace it with a substitution variable. we will
        * write out all the substitutions to a separate file the user can fill in. we will write out a new test variant
        * of the pipeline config and its substitution file which can be then fed into concourse for pipeline creation
        *
        :param write_out_test_yamls: after we make all the substitutions, do we also write out the new content?
        :return: None
        """

        temp_list = list()  # list of tuples (original/sub)

        # for each resource in the resources block
        for resource in self.yaml_config["resources"]:
            if resource['type'] == 'docker-image':
                temp_list += self.parse_resource_docker_image(resource)

            if resource['type'] == 'git':
                # git we will handle differently in that we will perform the substitutions but we also need to perform
                # the clone/forks
                original_repo, user_fork = self.parse_resource_git(resource)
                self.git_repos.append(original_repo)
                self.git_forks.append(user_fork)

            if resource['type'] == 'artifactory':
                temp_list += self.parse_resource_artifactory(resource)

            if resource['type'] == 'pool':
                temp_list += self.parse_resource_pool(resource)

            if resource['type'] == 'slack-notification':
                temp_list += self.parse_resource_slack_notification(resource)

        sub_list = list()
        # get a list (cleaned up) of the sub vars used
        for element in temp_list:
            if element is not None and element[1]:
                # strip out the (( and )) to clean it up
                pattern = r"^\(\((.*)\)\)$"
                match_obj = re.match(pattern, element[1], re.I)

                if match_obj:
                    sub_list.append((element[0], match_obj.group(1)))
                else:
                    sub_list.append((element[0], element[1]))

        # write out a yaml that contains a list of the substitution variables we used
        if sub_list and write_out_test_yamls is True:
            substitution_var_file = "{}-test_env_vars.yaml".format(os.path.splitext(self._yaml_file)[0])

            self.write_out_sub_var_file(substitution_var_file, sub_list)

            # write out the test variant of the production pipeline config
            yaml = YAML()  # default, if not specfied, is 'rt' (round-trip)
            test_yaml_config = "{}-test.yaml".format(os.path.splitext(self._yaml_file)[0])
            with open(test_yaml_config, 'w') as yaml_file :
                yaml.dump(self.yaml_config, stream=yaml_file)

    def write_out_sub_var_file(self, filename, sub_var_list):
        """
        * write out the substitution file
        :param filename: name of the file to use
        :param sub_var_list: list of sub vars that were generated
        :return: None
        """

        # add this header so the user will not only have context - but direction on proceed
        header =\
"""###############################################################################
#
# Note: Substitution variables are in the format of how they appeared in the resource object
#
# 1.) Resource Type
# 2.) Resource Name
# 3.) Resource Field
#
# ex.
#
# - name: golang-ci-image
#   type: docker-image
#   source:
#     repository: docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local/genctl/golang-ci
#     tag: 1.10.3.20180622
#     username: ((wcp-genctl-docker-local-artifactory-username))
#     password: ((wcp-genctl-docker-local-artifactory-token))
#
# In the above, the "field" repository will translate:
#
# from: docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local will trans
# to  : ((docker-image_golang-ci-image_repository))/genctl/golang-ci
#
# using: ((<type>_<name>_<field>))
#
###############################################################################
"""

        self.logger.info("Substitutions were made. Creating substitutions file: {}".format(filename))

        # write the substitutions file
        with open(filename, 'w') as sv_file:

            sv_file.write(header)  # write out the header
            sv_file.write("\n")

            for sub in sub_var_list:
                sv_file.write("{}: # {}\n".format(sub[1], sub[0]))

    def parse_resource_git(self, resource):
        """
        * loop through all the git types and denote all repos and swap in the uri of the repo had it been forked already
        *
        :param resource: resource block
        :return: original uri/user created fork
        """

        # some git resource types also carry the 'repo' tag. in those cases, we need to massage the path to reflect
        # the user within its path
        if 'repo' in resource['source']:
            user_repo = "{}/{}".format(self.git_user, resource['source']['repo'].split('/')[1])
            resource['source']['repo'] = user_repo

        original_uri = resource['source']['uri']

        # ex. git@github.ibm.com:eric-w-gustafson/genctl-ci.git
        pattern = r'(.*)\.com:.*\/(.*)\.git$'
        self.logger.debug("pattern: {}".format(pattern))
        self.logger.debug("search: {}".format(original_uri))
        match_obj = re.match(pattern, original_uri, re.I)

        user_fork = ""

        if match_obj:
            user_fork = "{}.com:{}/{}.git".format(match_obj.group(1), self.git_user, match_obj.group(2))
            self.logger.debug("user repo: {}".format(user_fork))
            # swap in the user fork
            resource['source']['uri'] = user_fork
        else:
            raise ValueError("Couldn't determine the user repo from \"{}\" using pattern; \"{}\"".format(original_uri,
                                                                                                         pattern))
        self.logger.debug("git uri: {}".format(original_uri))

        # return the name of the original repo along with what the user fork would translate to
        return original_uri, user_fork

    def parse_resource_docker_image(self, resource):
        """
        * parse out the hardcodes used for docker-image resources
        *
        :param resource: dict of resource config
        :return: the original/substitution vars created/used (to be backfilled by the user)
        """

        return self.parse_resource_common(resource, 'repository', r'.*\.com(.*)')

    def parse_resource_artifactory(self, resource):
        """
        * parse out the hardcodes used for artifactory resources
        *
        :param resource: dict of resource config
        :return: the original/substitution vars created/used (to be backfilled by the user)
        """

        return self.parse_resource_common(resource, 'endpoint', r'(.*)\/\/.*\.com(.*)', group=2)

    def parse_resource_pool(self, resource):
        """
        * This resource will be done at a later time.
        :param resource: dict of resource config
        :return:
        """
        return []

    def parse_resource_slack_notification(self, resource):
        """
        * parse out the hardcodes used for slack-notification resources
        *
        :param resource: dict of resource config
        :return: the original/substitution vars created/used (to be backfilled by the user)
        """

        return self.parse_resource_common(resource, 'uri')

    def parse_resource_common(self, resource, repo_or_endpoint_or_url, regex=None, group=1):
        """
        * code to perform parsing of similar resource types
        :param resource: resource block
        :param repo_or_endpoint_or_url: tag we are interested in
        :param regex: regex used to perform substitution
        :param group: what match group are we interested in?
        :return: the original/sub var that was used
        """

        self.logger.debug("Parsing resource: {}".format(resource['name']))

        subbed = list()

        # parse the tag
        subbed.append(self.process_repo_or_endpoint_or_url(resource, repo_or_endpoint_or_url, regex, group))

        # parse credentials, if they exist
        subbed.append(self.process_credential(resource, 'username'))

        subbed.append(self.process_credential(resource, 'password'))

        return subbed

    def validate_and_read_yaml(self):
        """
        * open the yaml and attempt to read it in. if we can read it in, absorb its config.
        * if we fail for any reason, except
        *
        * return: None
        """

        try:
            with open(self._yaml_file, "r") as myfile:
                yaml = YAML()  # default, if not specfied, is 'rt' (round-trip)
                self.yaml_config = yaml.load(myfile)

        except Exception as e:
            raise ConfigError("Unable to parse yaml: {}. reason: {}".format(self._yaml_file, e))

    def get_docker_images(self, third_party_only=False):
        """
        * Returns all associated docker images
        *
        :param third_party_only: filter only third party?
        :return: list of image/tag
        """

        internal_docker_registries = ['na.artifactory.swg-devops.com',
                                      'docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local']

        images = list()

        # for each resource in the resources/resource_types block
        for resource in self.yaml_config["resources"] + self.yaml_config["resource_types"]:
            repo = ""
            tag = "latest"

            if resource['type'] == 'docker-image' :
                if 'repository' in resource['source']:
                    if third_party_only is True:
                        if re.search('({}|{}|{})'.format(internal_docker_registries[0],
                                                         internal_docker_registries[1],
                                                         internal_docker_registries[2]),
                                     resource['source']['repository']):
                            continue

                    repo = resource['source']['repository']
                    self.logger.debug(repo)

                    # if no tag is specified or tag is specified but empty - we are latest
                    if 'tag' in resource['source'] and resource['source']['tag'] is not None:

                        tag = resource['source']['tag']
                        self.logger.debug(tag)

                    # this will be 'latest', if not explicitly set
                    images.append((repo, tag))

        return images

    def create_git_clones_and_forks(self):
        """
        * spin off and clone/fork all found resources as identified in the pipeline yaml
        :return: None
        """

        # remove any duplicate entries prior to iterating the loop. some pipelines
        # may have the repo listed twice (fab2/3)
        for git_repo in list(set(self.git_repos)):
            try:
                clone_and_fork_repo(git_repo, self.sandbox_dir)
            except:
                self.logger.error("There was an issue with clone/fork!")
                # re-raise to the caller
                raise
