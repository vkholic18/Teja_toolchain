import logging
import os,sys
import yaml

def set_up_logger(log_level):
    """
    Configures logger and formatting
    Returns:
        Logger object
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    if not logger.handlers:
        logger.propagate = 0
        logger.addHandler(handler)
        logger.setLevel(log_level)

    return logger

def parse_env(required_vars):
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args
    
def load_yaml(file_path):
    logger = logging.getLogger()

    try:
        with open(file_path) as f:
            dictionary = yaml.safe_load(f)
        return dictionary
    except yaml.YAMLError:
        logger.info(f"YAML is not valid, exiting")
        sys.exit(1)