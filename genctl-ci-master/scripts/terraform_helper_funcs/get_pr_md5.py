
import github
import os
import logging
import argparse
import sys

summary_search_string = "#### Terraform Summary ####"
md5_search_string = "#### MD5:"


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


def parse_args():
    """
    Parse the arguments passed when calling this file
    """
    parser = argparse.ArgumentParser(
        description="Parser to take required and optional values for the script")
    parser.add_argument('-o', '--out-file', help="MD5 output file",
                        required=True, dest="out_file")
    parser.add_argument('-s', '--sha', help="Sha of the PR",
                    required=True, dest="sha")
    args = parser.parse_args()
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
        'GITHUB_API_KEY',
        'GITHUB_API_URL',
        'WORKSPACE_REPO',
        'WORKSPACE_ORG',
    ]

    for var in required_vars:
        if var in os.environ.keys() and not os.environ[var] == '':
            args[var.lower()] = os.environ[var]
        else:
            logger.error(f"Missing required env variable, {var}")
            exit(1)

    return args


def write_file(file_path, content):
    logger = logging.getLogger()
    try:
        # After the code running under the "with" command is out of scope, "open_file" is automatically closed
        with open(file_path, 'w') as open_file:
            open_file.write(content)
    except IOError as e:
        logger.error("Failed to write to {}".format(file_path))
        logger.error(e)
        sys.exit(1)


def get_latest_pr(repo, pr_sha):
    pulls = repo.get_pulls(state='closed')
    found = False
    for pr in pulls:
        if pr.merge_commit_sha == pr_sha:
            pull_request = pr
            found = True
            break
    print(
        f"Found pull request associated with merge commit: {pr_sha}, PR number #{pull_request.number}, title: {pull_request.title}")
    return pull_request, found


def extract_md5sum(pr):
    for comment in pr.get_issue_comments():
        if summary_search_string in comment.body:
            lines = comment.body.split('\n')
            for line in lines:
                if line.startswith(md5_search_string):
                    value = line.split(":")[1].strip()
    print(f"PR MD5 file found is {value}")
    return value


def main():
    args = parse_args()
    env_args = parse_env()
    # set up ghe
    gh = github.Github(
        login_or_token=env_args['github_api_key'],
        base_url=env_args['github_api_url']
    )
    ws = f"{env_args['workspace_org']}/{env_args['workspace_repo']}"
    repo = gh.get_repo(ws)
    pr, found = get_latest_pr(repo, args.sha)
    if found:
        md5 = extract_md5sum(pr)
        write_file(args.out_file, md5)
    else:
        print("Unable to locate the MD5SUM, exiting...")
        sys.exit(1)


if __name__ == "__main__":
    main()