#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# Description:
#    Deployment on VE
#
# Env:
#    COMPONENT_HASH: Workspace component hash.

#
# Use:
#    python3 deploy-ve-client.py

import os
import logging
import json
import time
import requests

component_hash = os.environ['COMPONENT_HASH']
ve_user = os.environ['VE_USER']
ve_pass = os.environ['VE_PASS']
task = os.environ['VE_TASK']
reservation_uuid = os.environ['VE_RESERVATION_UUID']
service_endpoint = os.environ['VE_SERVICE_ENDPOINT']

bundle_name = os.environ['COMPONENT']
image_url = os.environ['IMAGE_URL']
image_tag = os.environ['IMAGE_TAG']
image_cmd = os.getenv('IMAGE_CMD', "")

rias_flag = os.environ['DEPLOY_RIAS']
genctl_flag = os.environ['DEPLOY_GENCTL']
genctl_flavor = os.environ['FLAVOR']
bundle_phase = os.environ['VE_BUNDLE_CATEGORY']
ve_branch = os.getenv('VE_BRANCH', "heads/ci-stable")

success_status_code = 200
success_accepted = 202
success_no_content = 204


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


def query(logger, service_url, endpoint, operation, arguments):
    """
    Queries a Hades endpoint and returns json data
    Returns:
        json: data
    """
    try:
        if operation == "delete":
            logger.info("DELETE {}".format(arguments))
            if arguments != "":
                endpoint_response = requests.delete(service_url + endpoint,
                                                    auth=(ve_user, ve_pass),
                                                    data=arguments)
            else:
                endpoint_response = requests.delete(service_url + endpoint,
                                                    auth=(ve_user, ve_pass))
        elif operation == "post":
            logger.info("POST {}".format(arguments))
            if arguments != "":
                endpoint_response = requests.post(service_url + endpoint,
                                                  auth=(ve_user, ve_pass),
                                                  data=arguments)
            else:
                endpoint_response = requests.post(service_url + endpoint,
                                                  auth=(ve_user, ve_pass))
        else:
            endpoint_response = requests.get(service_url + endpoint,
                                             auth=(ve_user, ve_pass))

        # logger.info(endpoint_response.text)
        if endpoint_response.status_code != success_status_code and \
                        endpoint_response.status_code != success_no_content and \
                        endpoint_response.status_code != success_accepted:
            logger.error(
                "Status code did not match success {}, exiting ".format(
                    success_status_code))
            logger.error(
                "Status code was {}".format(endpoint_response.status_code))
            logger.error(
                "Error message returned was {}".format(endpoint_response.text))
            return endpoint_response.status_code, ""

        return endpoint_response.status_code, endpoint_response

    # Unreachable exception
    except requests.exceptions.RequestException as e:
        print("endpoint server \"" + service_url + "\" cannot be reached.")
        logger.error(
            "Status code did not match success {} cannot be reached. ".format(
                service_url))
        logger.error(e)
        return e


def create_ve(logger):
    startTime = time.time()

    logger.info(
        "Beginning Create of Virtual Environment for {} with hash {} against"
        " endpoint {}".format(
            bundle_name, component_hash, service_endpoint))

    # Claim a system to create a VE on
    # v1/reservation claim
    json_object = {
        "machine_tags": {
            "region": "dal13g4",
            "machine_type": "rack_sled",
            "machine_configuration": "traditional"
        },
        "time_to_live_hours": 3
    }
    code, data = query(logger, service_endpoint, "/v1/reservation", "post",
                       json.dumps(json_object))

    if code != success_status_code:
        logger.error("Error making reservation. Returning with no uuid")
        return 1

    logger.info(data.text)
    json_data = json.loads(data.text)
    reservation_uuid = json_data["uuid"]
    logger.info(
        "Reserved system: {} with "
        "reservation tags: {}".format(reservation_uuid,
                                      json_data[
                                          "reservation_tags"]))

    # Convert strings to bool
    deploy_rias = False
    if rias_flag.lower() == 'true':
        deploy_rias = True

    deploy_genctl = False
    if genctl_flag.lower() == 'true':
        deploy_genctl = True

    json_object = {
        "reservation_uuid": reservation_uuid,
        "operation_type": "CREATE",
        "build_options": {
            "hephaestus_branch": ve_branch,
            "genctl_flavor": genctl_flavor,
            "run_virsh_validation": False,
            "deploy_rias": deploy_rias,
            "deploy_genctl": deploy_genctl,
            "release_reservation_on_failure": True
        }
    }

    # if we are customizing a component, smotainer uses a vanilla VE
    if bundle_name != "smotainer":
        # Make a VE on claimed system
        # v1/operation
        json_object = {
            "reservation_uuid": reservation_uuid,
            "operation_type": "CREATE",
            "build_options": {
                "hephaestus_branch": ve_branch,
                "genctl_flavor": genctl_flavor,
                "run_virsh_validation": False,
                "deploy_rias": deploy_rias,
                "deploy_genctl": deploy_genctl,
                "release_reservation_on_failure": True,
                "partial_build_inventory": {
                    "bundletypes": [
                        {
                            "categories": [bundle_phase],
                            "bundles": [
                                {
                                    "name": bundle_name,
                                    "url": image_url,
                                    "tag": image_tag,
                                    "cmd": image_cmd
                                }
                            ]
                        }
                    ]
                }

            }
        }

    code, data = query(logger, service_endpoint, "/v1/operation", "post",
                       json.dumps(json_object))

    if code != success_status_code and code != success_accepted and code != success_no_content:
        logger.error("Error starting create operation. ")
        print(reservation_uuid, "")
        return 2

    json_data = json.loads(data.text)
    status = json_data["status"]
    operation_uuid = json_data["uuid"]
    logger.info("Created operation {} on "
                "reservation {} to create a VE.".format(operation_uuid,
                                                        reservation_uuid))

    sleep_time = 15  # Short wait in case of initial failures
    failed = False
    done = False
    initial_create = True

    # Check status; if failed, fail. Otherwise loop until done or failed
    if status == "ERROR" or status == "INVALID":
        logger.error("v1/operation Failed to Create VE: {} ".format(data.text))
        failed = True

    # Wait for the VE to finish coming up. Wait 30 seconds then 5 minutes and
    # then 30 second intervals until the status reaches an end state
    while not failed and not done:
        time.sleep(sleep_time)

        # After the create we want to wait a decent interval before we bother
        # to check again.
        if initial_create:
            sleep_time = 300  # 5 minutes
            initial_create = False
        else:
            sleep_time = 30  # 30 seconds

        endpoint = "/v1/operation/" + operation_uuid
        code, data = query(logger, service_endpoint, endpoint, "GET", "")
        json_data = json.loads(data.text)
        status = json_data["status"]
        try:
            build_url = json_data["automation_information"]["build_url"]
        except TypeError:
            build_url = "--"
        if status == "ERROR" or status == "INVALID":
            logger.error(
                "v1/operation Failed to Create VE: {} ".format(data.text))
            failed = True
        elif status == "COMPLETE":
            done = True
            logger.info("VE operation finished with response: {} ".format(
                data.text))
        elif status == "PENDING":
            logger.info("VE operation {} is pending".format(operation_uuid))
        else:
            logger.info("VE operation {} is running at {}".format(operation_uuid, build_url))

    process_time = (time.time() - startTime) / 60  # in minutes

    if status == "COMPLETE":

        logger.info("Create a VE for this task COMPLETE in {} minutes.".format(
            process_time))
        environment_details = json_data["environment_details"]
        logger.info("Environment detail json: {}".format(environment_details))
        identifier = environment_details["identifier"]
        genctl_kubernetes_address = environment_details["genctl_kubernetes_address"]
        print(reservation_uuid, identifier, genctl_kubernetes_address)
    else:
        logger.info("Create a VE for this task FAILED in {} minutes.".format(
            process_time))
        print(reservation_uuid, "")
        return 2


def delete_ve(logger):
    logger.info(
        "Beginning Delete of Virtual Environment for reservation {} "
        "against endpoint {}".format(
            reservation_uuid, service_endpoint))

    # Clean up
    # v1/reservation release
    # and operation delete

    json_object = {
        "reservation_uuid": reservation_uuid,
        "operation_type": "DESTROY",
    }
    code, data = query(logger, service_endpoint, "/v1/operation", "post",
                       json.dumps(json_object))
    if code != success_no_content and code != success_accepted and code != success_status_code:
        return 1
    else:
        return 0


def main():
    logger = setup_logger()

    if task.lower() == "create":
        result = create_ve(logger)
        exit(result)
    elif task.lower() == "delete":
        result = delete_ve(logger)
        exit(result)
    else:
        logger.error("No valid VE operation requested")


if __name__ == "__main__":
    main()
