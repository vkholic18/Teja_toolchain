#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
# Script to create/update GitHub check status to latest commit in a PR
# GITHUB_API_URL and GITHUB_API_KEY passed via enviornment variables
#

import argparse
import os
import sys
import github

def parse_args(cl_args):
    # Parses required and opt argumets from command line and return Namespace

    args = ['org', 'repo', 'pr', 'state', 'target_url', 'context']
    parser = argparse.ArgumentParser(description="GitHub check state updater")

    for arg in args:
        parser.add_argument(arg, action="store")
    
    parser.add_argument('--retries', dest='retries', action='store',
        default=3, type=int)
    
    return  parser.parse_args(cl_args)

def create_gh_object(retries):
    # Returns a GitHub access object give number of retires
    # and API credentials from environment

    return github.Github(
        base_url=os.environ['GITHUB_API_URL'],
        login_or_token=os.environ['GITHUB_API_KEY'],
        retry=retries
    )

def get_pr_head_commit(pr, repo):
    # Returns a GitHub commit object of the last commit in the given repo/PR

    head_commit = repo.get_pull(int(pr))
    head_sha = head_commit.head.sha

    return repo.get_commit(sha=head_sha)

def post(args, commit):
    # Creates a status check on the given commit with the given parameters
    # parsed from the command line

    commit.create_status(
        state=args.state,
        target_url=args.target_url,
        context=args.context,
        description="build {0}".format(args.state)
    )
    
    print("Posted {0} state".format(args.state))

def main():
    args = parse_args(sys.argv[1:])

    gh = create_gh_object(args.retries)
    repo = gh.get_repo("{0}/{1}".format(args.org, args.repo))
    commit = get_pr_head_commit(args.pr, repo)

    post(args, commit)

if __name__ == "__main__":
    main()
