#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
# Script to assign taas group users to their managers
#
# Using blueapi - BluePages Employee Directory API
#

###############################################################################
# I M P O R T S
###############################################################################

import argparse
import requests
import os
import logging
import sys
import yaml
from http import HTTPStatus
from string import Template
from Email import Email

w3_email_api = "/common/run/bluepages/email/"
w3_cnum_api = "/common/run/bluepages/cnum/"
DEFAULT_TEMPLATE = 'emailTemplate.txt'
W3_TOKEN = os.environ['W3_TOKEN']

###############################################################################
# F U N C T I O N S ###########################################################
###############################################################################


def setup_logger(debug_enabled=False):
    """
    * Setup up the logger and return a handle
    """
    # set the logger to show the time/level/message
    # stdout logging is sufficient

    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    # This gives more info for debugging
    # formatter = logging.Formatter('%(asctime)s {%(funcName)s:%(lineno)d} %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger_setup = logging.getLogger()
    logger_setup.addHandler(handler)
    logger_setup.setLevel(
        logging.DEBUG if debug_enabled is True else logging.INFO)
    logger_setup.info("Logger level set to \"{}\"".format(logger_setup.level))

    return logger_setup


def open_file(infile):
    """
    Open file from stream
    Return:
        Content: file content
    """
    logger = logging.getLogger()
    try:
        with open(infile, 'r') as f:
            content = f.read()
    except IOError:
        logger.error("Unable to open file for reading ({})".format(infile))
        sys.exit(1)

    return content


def write_content(outfile, content, format='.yaml'):
    """
    Writes mapped content to output file

    Args:
        outfile (string): name of the output file.
        content (dict): content of the dictionary.
    """
    with open(outfile + format, 'w') as new_file:
        yaml.safe_dump(content, new_file)


def remove_whitespace(user_list):
    """
    Remove any trailing or preceding whitespaces
    Return:
        user_list (list): list without trailing whitespaces
    """
    user_list = [user.strip(' ') for user in user_list]
    return user_list


def parse_users_and_group(users_inflie):
    """
    Parse the artifactory group name and the users list from infile
    Args:
        users_inflie (string): raw infile of artifactory group and user email list
    Returns:
        artif_group, user_formatted: artifactory group and the formatted users list
    """
    # taas group users inflile sample wcp.test: user1@ibm.com, user2@ibm.com ...
    logger = logging.getLogger()
    artif_group = users_inflie.split(':')[0]
    logger.info(
        f"The artifactory group parsed from file is: \"{artif_group}\"")
    user_list = users_inflie.split(':')[1].strip()
    user_formatted = user_list.split(',')
    user_formatted = remove_whitespace(user_formatted)
    return artif_group, user_formatted


def set_parser():
    """
    Parse the arguments passed when calling this file.
    Returns:
        parser (parser object)
    """
    parser = argparse.ArgumentParser(
        description='Assign users to their managers.')
    parser.add_argument('-f', '--file', dest='infile',
                        help='The input file of the artifactory user list, File content format: artifactory_group: test1@ibm.com, test2@ibm.com...')
    parser.add_argument('-e', '--endpoint-url',
                        default="https://w3.api.ibm.com", dest="w3_url", help="IBM w3 endpoint URL")
    parser.add_argument('-o', '--out-file', dest="out_file",
                        help='The output file of the script artifact')
    parser.add_argument('-d', '--debug', help="When used, enables debug mode. No args", required=False,
                        dest="debug", default=False, action='store_true')
    return parser.parse_args()


def get_manager_email_from_uuid(session, w3_url, manager_uuid, user_email):
    """
    Maps manager uuid to email
    Args:
        session (request object): current HTTP session
        w3_url (string): w3 base api url
        manager_uuid (string): manager uuid
        user_email (string): user email
    Returns:
        manager_email (string): manager email
    """
    logger = logging.getLogger()
    attributes_list = "email"
    cnum_req_url = (f"{w3_url}{w3_cnum_api}{manager_uuid}/{attributes_list}")
    response = session.get(url=cnum_req_url)
    entries = response.json()['search']['entry']
    for entry in entries:
        attributes = entry['attribute']
        for attr in attributes:
            if attr['name'] == 'email':
                manager_email = attr['value'][0]
                if manager_email:
                    return manager_email
                else:
                    logger.error(
                        f"Manager email for user {user_email} was not found")
                    return None


def verify_endpoint_status(endpoint_url, auth):
    """
    Verify endpoint is reachable prior to making HTTP calls

    Args:
        endpoint_url (string): endpoint url
        auth (object): headers containing auth
    """
    logger = logging.getLogger()
    try:
        logger.debug(
            "Verifying connection to endpoint \"{}\"".format(endpoint_url))
        w3_endpoint_check = requests.head(
            endpoint_url, headers=auth, allow_redirects=True)
        if w3_endpoint_check.status_code != HTTPStatus.OK:
            logger.error("Status code {} != {}".format(
                str(w3_endpoint_check.status_code), str(HTTPStatus.OK)))
            logger.info("Please check that the login credentials & configuration are still valid.")
            sys.exit(1)
    except requests.exceptions.RequestException as e:
        logger.error(
            "Endpoint server \"{}\" cannot be reached.".format(endpoint_url))
        logger.error(e)
        sys.exit(1)


def add_to_dictionary(manager_dic, artifactory_group, key, value):
    """
    Add a key to dictionary, if the key was not found init as an empty list, otherwise append value to key

    Args:
        manager_dic (list): dictionary to append key to
        artifactory_group (string): artifactory group name
        key (string): key we want to add
        value (string): value of the key we want to append to
    """
    if key not in manager_dic[artifactory_group].keys():
        manager_dic[artifactory_group][key] = []
    manager_dic[artifactory_group][key].append(value)


def build_manager_map(session, user_list, w3_url, artifactory_group):
    """
    Maps between user in a set taas group to their managers
    Args:
        session: current HTTP session
        user_list (list): list of space delimited user emails
        w3_url (string): w3 base api url
        artifactory_group (string): artifactory taas group name
    Returns:
        manager_email (list): dictionary with keys of manager emails and value of users list
    """
    logger = logging.getLogger()
    manager_dic = {}
    manager_dic[artifactory_group] = {}
    removed_users = []
    attributes_list = "manager"
    for email in user_list:
        # Pre request to endpoint with the user email
        email_req_url = (f"{w3_url}{w3_email_api}{email}/{attributes_list}")
        # Get user manager UUID
        response = session.get(url=email_req_url)
        entries = response.json()['search']['entry']
        if entries:
            for entry in entries:
                attributes = entry['attribute']
                for attr in attributes:
                    if attr['name'] == 'manager':
                        # Manager value is an array with one value and it's a string, we need to strip out the UID
                        # i.e ['uid=XXXX, value1=XXXX, value2=XXXX']
                        manager_uuid = attr['value'][0].split(
                            ',')[0].replace('uid=', '')
                        # Retrieve the manager email from the UUID
                        manager_email = get_manager_email_from_uuid(
                            session,
                            w3_url,
                            manager_uuid,
                            email)
                        if manager_email:
                            add_to_dictionary(
                                manager_dic, artifactory_group, manager_email, email)
                        else:
                            logger.error(
                                f"Unable to find {email} manager information")
        else:
            logger.debug(f"User email {email} was not found on endpoint")
            removed_users.append(email)

    sorted_users = dict(sorted(manager_dic.items()))
    # Add user that were not found
    if len(removed_users) != 0:
        manager_dic[artifactory_group]['removed'] = removed_users
    return sorted_users


def prepare_template_body(template_filename, artifactory_group_name, users, number_of_expiration_days=7):
    """
    Uses a template file i.e text.txt to generate a template for the email body
    Args:
        template_filename (string): specify the text template file name
        artifactory_group_name (string): the artifactory group name
        users (string): a formatted string of users (delimited by newline)
        number_of_expiration_days (int, optional): number of expiration days for artifactory access to be revoked. Defaults to 7.

    Returns:
        msg_body(string): returns a formatted template using the input information
    """
    with open(template_filename, 'r', encoding='utf-8') as template_file:
        template_file_content = template_file.read()
        template = Template(template_file_content)
    msg_body = template.substitute(
        ARTIFACTORY_GROUP_NAME=artifactory_group_name, USER_LIST=users, NUMBER_OF_DAYS=number_of_expiration_days)
    return msg_body


def send_emails(template_filename, artifactory_group_name, users_dictionary):
    """
    Send emails to managers with a formatted template containing subordinates
    Args:
        template_filename (string): template filename to use
        artifactory_group_name (string): artifactory group name
        users_dictionary (dictionary): dictionary created containing artifactory map to managers 
    """
    logger = logging.getLogger()
    email = Email()
    for manager_email, users in users_dictionary[artifactory_group_name].items():
        if manager_email != 'removed':
            # Add a approve/deny link per user
            users_email_list = [f"{user} <link-placeholder-{user}>" for user in users]
            formatted_users = ('\n').join(users_email_list)
            msg_body = prepare_template_body(
                template_filename, artifactory_group_name, formatted_users)
            logger.debug(
                f"Sending email to: {manager_email}, msg body: {msg_body}")
            # TODO: Comment out when not performing a dry run, do not send anything for now
            # email.sendEmail(recipientList=[manager_email], subject='Artifactory audit', body=msg_body)

###############################################################################
# M A I N #####################################################################
###############################################################################


def main():
    args = set_parser()
    debug = args.debug
    logger = setup_logger(debug)
    # Open input content file for given artifactory group and users
    # The file format should be : ARTIFACTORY_GROUP_NAME: user1@ibm.com, user2@ibm.com, user3@ibm.com...
    users = open_file(args.infile)
    arti_group, user_list = parse_users_and_group(users)

    # Create connection to endpoint
    session = requests.Session()
    headers = {
        'x-ibm-client-id': W3_TOKEN,
        'accept': "application/json"
    }
    session.headers.update(headers)
    verify_endpoint_status(args.w3_url, headers)

    # Build the dictionary
    manager_map_dic = build_manager_map(
        session, user_list, args.w3_url, arti_group)

    # Output result to a file
    if args.out_file:
        write_content(args.out_file, manager_map_dic)

    # Send emails
    script_dir = os.path.dirname(__file__)
    template_path = os.path.join(script_dir, DEFAULT_TEMPLATE)
    send_emails(template_path, arti_group, manager_map_dic)
    logger.info("Operation is finished.")


if __name__ == '__main__':
    main()
