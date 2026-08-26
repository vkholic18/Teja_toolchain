# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
# Description: Awaits and collects comments done by dev mzone mgmt tool on a commit and exits with 
#              approriate exit code depending on the status returned by Jenkins job
# Env:
#    GHE_API_TOKEN: Token for Github API
#    GHE_API_URL: Url for the GitHub API
#    DEV_REGIONS_REPO_ORG_AND_NAME: Org and repo name for dev-regions
#    SHA_OF_COMMIT_WITH_TRIGGERED_PIPELINE_DETAILS: The SHA of the commit resulted from the merge of the PR on dev-regions

from random import randint
from time import sleep
import github
import logging
import os, sys

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


def parse_env():
    """
    Parses environment variables for required arguments
    Returns:
        args: a dict of arguments
    """
    logger = logging.getLogger()
    args = dict()

    required_vars = [
        'GHE_API_TOKEN',
        'GHE_API_URL',
        'DEV_REGIONS_REPO_ORG_AND_NAME',
        'SHA_OF_COMMIT_WITH_TRIGGERED_PIPELINE_DETAILS'
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args

def main():
    # Define logger and parse environment vars
    logger = set_up_logger()
    args = parse_env()

    # Instantiate GitHub object
    gh = github.Github(
        login_or_token=args['ghe_api_token'],
        base_url=args['ghe_api_url']
    )

    # Get the repository
    repo = gh.get_repo(args["dev_regions_repo_org_and_name"])

    # Get the commit object
    commit = repo.get_commit(sha=args['sha_of_commit_with_triggered_pipeline_details'])

    # Set the remaining attempts and the maximum attempts to do
    attempts_done = 0
    max_attempts = 120 #so we never run into a situation where this pipeline fails because DMM pipeline is not finished running

    # Loop
    while attempts_done < max_attempts:
        try:
            # Safely get commit comments
            try:
                comments = list(commit.get_comments())
            except github.GithubException as e:
                logger.warning(f"GitHub API error {e.status}: {getattr(e, 'data', None)}")

                # Retry on transient errors (403, 502, 503)
                if e.status in (403, 502, 503):
                    wait_time = randint(10, 30)
                    logger.info(f"Retrying after {wait_time}s due to GitHub error...")
                    sleep(wait_time)
                    attempts_done += 1
                    continue
                else:
                    # Non-recoverable GitHub error
                    raise

            except Exception as ex:
                logger.exception(f"Unexpected error while fetching comments: {ex}")
                # Wait a bit and try again
                sleep(randint(10, 30))
                attempts_done += 1
                continue

            num_comments = len(comments)

            # --- existing logic follows unchanged ---
            if num_comments == 2:
                comment_content = comments[1].body
                if 'No release bundle needs to be deployed, skipping Jenkins build!' in comment_content:
                    logger.info("No new release bundle needs to be deployed!")
                    logger.info("************************ Please find deployment related info below ************************")
                    for every in comments:
                        logger.info(every.body)
                    logger.info("*******************************************************************************************")
                    sys.exit(0)

            elif num_comments == 3:
                comment_content = comments[2].body
                if 'Jenkins_Run_Result' in comment_content:
                    status = comment_content.split(":")[-1].strip()
                    logger.info(f"The Jenkins pipeline has returned the status {status}")
                    logger.info("************************ Please find deployment related info below ************************")
                    for every in comments:
                        logger.info(every.body)
                    logger.info("*******************************************************************************************")

                    if status == "SUCCESS":
                        sys.exit(0)
                    else:
                        sys.exit(1)
                else:
                    logger.error("The comment is not in the expected format, exiting.")
                    sys.exit(1)

            # Info message if no matching comment yet
            logger.info(f"Could not find a comment for commit {args['sha_of_commit_with_triggered_pipeline_details']}...")
            logger.info("Will check again soon")

            # Increment attempts
            attempts_done += 1

            # Wait before retrying
            sleep(180)
            
        except Exception as e:
            logger.exception(f"Unexpected top-level error in monitoring loop: {e}")
            sleep(randint(30, 60))
            attempts_done += 1

    if attempts_done == max_attempts:
        if len(list(commit.get_comments())) != 3:
            logger.error(f"All comments not received in stipulated time")
            sys.exit(1)


if __name__ == "__main__":
    main()
    
