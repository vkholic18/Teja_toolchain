# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Sends slack notifications based on configuration given
#
# Env:
#    User Provided:
#       SOURCE_DIR_PATH: Path to the directory which contains outputs
#       PAYLOAD_FILE_PATH: Path to the concourse resource payload file
#    Automatically Provided by Concourse:
#       BUILD_PIPELINE_NAME: Name of the pipeline
#       BUILD_JOB_NAME: Name of the job
#       BUILD_ID: Unique build identifier number
#       ATC_EXTERNAL_URL: Url of concourse server
#
# Use:
#    python3 notify.py
#

import json
import logging
import os
import slack
import re
import sys
import traceback

from pipeline_config import PipelineConfig
from pipeline_meta import PipelineMeta
from slack.errors import SlackApiError

# Constants
DEFAULT_SLACK_CHANNEL = 'genctl-build'

def setup_logger():
    """
    Configures logger and formatting
    Returns:
        logger: logger object
    """

    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    return logger

def build_attachments(status, build_pipeline_name, build_job_name,
    build_id, atc_external_url):
    """
    Builds the message attachments payload
    Args:
        status: the status of the build
    Returns:
        attachments: the attachments payload as list of dicts
    """
    if status == 'start':
        verb = 'started'
        color = "#f1c40e"
    elif status == 'success':
        verb = 'succeeded'
        color = "#2ecc71"
    elif status == 'failure':
        verb = 'failed'
        color = "#e74c3c"
    elif status == 'abort':
        verb = 'aborted'
        color = "8b572a"

    long_name = "{0}/{1}".format(build_pipeline_name, build_job_name)
    attachments = [
        {
            "title": long_name,
            "title_link": f"{atc_external_url}/builds/{build_id}",
            "author_name": f"Build {verb.capitalize()}",
            "text": f"Build {build_id}",
            "fallback": f"{long_name} build {verb}",
            "color": color
        }
    ]

    return attachments

def send_slack_by_w3id(slack_client, w3id, attachments):
    """
    Translates w3id to direct slack channel id and calls send_slack_message
    Args:
        slack_client: slack web client
        w3id: the w3id (email) of the recipient
        attachments: slack message in attachments form
    """
    logger = logging.getLogger()
    try:
        channel = slack_client.users_lookupByEmail(email=w3id)['user']['id']
        send_slack_message(slack_client, channel, attachments)
    except SlackApiError as e:
        logger.error(
            f"Got an error attempting to send notifications to {w3id}, error: {e.response['error']}")
        sys.exit(1)
    except Exception:
        traceback.print_exc()
        sys.exit(1)

def build_notification_config(user_config, meta, status):
    """
    Builds notification config for notification resource
    Args:
        user_config: notification config from pipeline.yaml
        meta: pipeline metadata
        status: current status of the pipeline (success, fail, etc)
    Returns:
        notif_config: dictionary configuration of notification recipients
    """
    logger = logging.getLogger()
    notif_config = dict()

    if user_config:
        if status in user_config.keys():
            if 'author' in user_config[status]:
                notify_author = user_config[status].pop('author')
            else:
                notify_author = False

            notif_config = user_config[status]

            if notify_author:
                if 'w3ids' not in notif_config.keys():
                    notif_config['w3ids'] = []
                notif_config['w3ids'].append(meta.author_email)

    else:
        logger.info("Notification preferences not configured. " +\
            f"Sending to default channel, {DEFAULT_SLACK_CHANNEL}")
        notif_config = {'channels': [DEFAULT_SLACK_CHANNEL] }

    return notif_config

def send_slack_message(slack_client, channel, attachments):
    """
    Sends slack message to given channel
    Args:
        slack_client: slack web client
        channel: channel which will receive the message
        attachments: slack message in attachments form
    """
    slack_client.chat_postMessage(
        channel=channel,
        attachments=attachments
    )

def send_notifications(config, slack_client, attachments, dry_run):
    """
    Sends notifications based on the notification config
    Args:
        notif_config: dictionary configuration of notification recipients
        slack_client: slack web client
        attachments: the attachments payload as list of dicts
    """
    logger = logging.getLogger()

    if dry_run:
        logger.info("Dry-run enabled; notifications will not be sent")

    if 'w3ids' in config.keys():
        for w3id in config['w3ids']:
            if not dry_run:
                pattern = re.compile(r'^.*@.*ibm\.com$')
                if pattern.match(w3id):
                    send_slack_by_w3id(slack_client, w3id, attachments)
                    logger.info(f"Notification sent to {w3id}")
                else:
                    logger.error(f"W3id domain name is invalid {w3id}")
            else:
                logger.info(f"Notification sent to {w3id}")

    if 'channels' in config.keys():
        for channel in config['channels']:
            if not dry_run:
                send_slack_message(slack_client, channel, attachments)
            logger.info(f"Notification sent to {channel}")

def parse_payload(payload_file):
    """
    Parses resource payload for required and arguments
    Returns:
        payload_file: payload file Concourse passes to resource
    """
    logger = logging.getLogger()

    with open(payload_file) as f:
        payload = json.load(f)

    required_inputs = {
        'source': [
            'slack_token',
            'pipeline_type',
            'dry_run'
        ],
        'params': [
            'workspace-repo',
            'status'
        ]
    }

    args = dict()
    for config, params in required_inputs.items():
        for param in params:
            if param in payload[config].keys():
                args[param] = payload[config][param]
            else:
                logger.error(f"Missing required param, {param} in {config}")
                exit(1)

    return args

def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'SOURCE_DIR_PATH',
        'PAYLOAD_FILE_PATH',
        'BUILD_PIPELINE_NAME',
        'BUILD_JOB_NAME',
        'BUILD_ID',
        'ATC_EXTERNAL_URL'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args

def main():
    logger = setup_logger()
    env = parse_env()
    args = parse_payload(env['payload_file_path'])

    ws_path = os.path.join(env['source_dir_path'], args['workspace-repo'])
    pipe_config = PipelineConfig(ws_path, args['pipeline_type'])
    meta = PipelineMeta(ws_path)

    config = build_notification_config(
        pipe_config.notification,
        meta,
        args['status']
    )

    slack_client = slack.WebClient(token=args['slack_token'])
    attachments = build_attachments(
        args['status'],
        env['build_pipeline_name'],
        env['build_job_name'],
        env['build_id'],
        env['atc_external_url']
    )

    if config:
        send_notifications(config, slack_client, attachments, args['dry_run'])
    else:
        logger.info(f"Notification not configured for {args['status']}")

if __name__ == "__main__":
    main()
