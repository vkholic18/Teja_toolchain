"""
    Push a plan summary up to the pr under review.

    What is critical, here, is the md5sum of the generated plan file. This file will be used in the merge
    pipeline to determine if there has been any state drift since the pr pipeline was last ran
    (and subsequently approved)

"""

###############################################################################
# I M P O R T S
###############################################################################

import argparse
import logging
import os
import sys

import github

###############################################################################
# F U N C T I O N S
###############################################################################


def parse_args():
    """
    Parse the arguments passed when calling this file
    """
    parser = argparse.ArgumentParser(
        description="Parser to take required and optional values for the script")
    parser.add_argument('-pn', '--pr-number', help="PR number",
                        required=True, dest="pr_number")
    args = parser.parse_args()
    return args


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = {}

    required_vars = [
        'GITHUB_API_KEY',
        'GITHUB_API_URL',
        'WORKSPACE_REPO',
        'WORKSPACE_ORG',
        'INIT_STATUS',
        'FMT_STATUS',
        'VLDT_STATUS',
        'PLAN_STATUS',
        'MD5SUM',
        'PLAN_SUMMARY'
    ]

    for var in required_vars:
        if var in os.environ and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            sys.exit(1)

    return args


def set_up_logger():
    """
    Configures logger and formatting
    Returns:
        Logger object
    """
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    return logger


def status_mark(status):
    """
    Based on status, send back coded emote string

    Args:
        status (string): anything other than success earns a failure emote for the pr

    Returns:
        string: _description_
    """
    if status == "Success" or status == "NA":
        return ":green_circle:"
    else:
        return ":red_circle:"


def compose_comment_body(format_status, init_status, validate_status, plan_status, md5sum, plan_summary):
    """

    format and return the pr comment

    Args:
        format_status (string): pass/fail emote
        init_status (string): pass/fail emote
        validate_status (string): pass/fail emote
        plan_status (string): pass/fail emote
        md5sum (string): md5 hash of the plan file
        plan_summary (string): plan summary line from terraform output
    """

    pr_body = f"""
#### Terraform Summary ####
#### MD5: {md5sum}
#### Terraform Format and Style `{format_status}` {status_mark(format_status)}
#### Terraform Initialization `{init_status}` {status_mark(init_status)}
#### Terraform Validation `{validate_status}` {status_mark(validate_status)}
#### Terraform Plan `{plan_status}` {status_mark(plan_status)}
#### {plan_summary}
"""

    return pr_body


###############################################################################
# M A I N
###############################################################################


def main():
    """
    Pull together a plan summary and post as a pr comment
    """
    set_up_logger()
    args = parse_args()
    env_args = parse_env()

    # get our payload ready
    body = compose_comment_body(env_args['fmt_status'], env_args['init_status'],
                                env_args['vldt_status'], env_args['plan_status'], env_args['md5sum'],
                                env_args['plan_summary'])

    # set up ghe
    gh_obj = github.Github(
        login_or_token=env_args['github_api_key'],
        base_url=env_args['github_api_url']
    )
    gh_ws = f"{env_args['workspace_org']}/{env_args['workspace_repo']}"
    gh_repo = gh_obj.get_repo(gh_ws)
    gh_pr = gh_repo.get_pull(int(args.pr_number))
    gh_pr.create_issue_comment(body)


if __name__ == "__main__":
    main()
