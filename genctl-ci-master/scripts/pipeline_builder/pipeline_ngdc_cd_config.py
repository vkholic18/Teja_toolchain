# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Contains PipelineConfig class which parses and represents the pipeline
#    configuration defined in the developer repository
#    Inherited from pipeline_builder/pipeline_config.py

import logging
import os
import yaml

import config_validator_cd

class PipelineConfig:
    """
    This class represents the pipeline configuration defined in the repository
    """
    def __init__(self, ws_path, PIPELINE_CONFIG_PATH='hack/cd/promotion.yaml', pipe_type=None):
        self._pipe_type = pipe_type

        self.config = {}
        self._parse_config(ws_path, PIPELINE_CONFIG_PATH)

    @property
    def notification(self):
        """
        :type: dict
        """
        if self._pipe_type and self._pipe_type in self.config.keys() and\
            'notification' in self.config[self._pipe_type].keys():

            return self.config[self._pipe_type]['notification']

        else:
            return None

    @property
    def deployment(self):
        """
        :type: dict
        """
        if 'deployment' in self.config.keys():
            return self.config['deployment']

        else:
            return None

    @property
    def environment(self):
        """
        :type: dict
        """
        if 'environment' in self.config.keys():
            return self.config['environment']

        else:
            return None

    @property
    def functional_tests(self):
        """
        :type: string
        """
        if 'functional_tests' in self.config.keys():
            return self.config['functional_tests']

        else:
            return None

    def _parse_config(self, ws_path, PIPELINE_CONFIG_PATH):
        """
        Opens and parses yaml config file into dictionary
        Args:
            ws_path: path to workspace
        """
        logger = logging.getLogger()

        config_path = os.path.join(ws_path, PIPELINE_CONFIG_PATH)
        logger.info(f"Parsing {config_path} for pipeline configuration")

        if os.path.exists(config_path):
            
            config_validator_cd.validate(config_path)

            with open(config_path, 'r') as stream:
                config = yaml.safe_load(stream)

            self.config = config
            print(config)

        else:
            logger.info(f"{config_path} not configured. Applying defaults")
            self.config = dict()