from math import ceil
from datetime import datetime

def get_statuses_from_commit(commit,ci_checks_prefix):
    """
        Gets a commit and return the statuses of that commit

        Returns: A set of strings containing the statuses of a particular commit
    """

    # Declare an empty set
    result = set()

    # Get the statuses for a specific commit
    statuses = commit.get_statuses()

    # Iterate over the statuses
    for status in statuses:

        # Assume we will take the check as it comes
        actual_check_to_add = status.context
        
        # If is a "CI check", then remove the prefix
        if ci_checks_prefix in actual_check_to_add:
            actual_check_to_add = actual_check_to_add.split('/')[1]
        
        result.add(actual_check_to_add)
    
    # Return
    return result

def is_commit_from_last_week(commit,one_week_ago):
    """
        Gets a commit and returns True if the commit is from last week or False otherwise
        (If there is exception we assume False)

        Returns: boolean
    """
    try:
        formatted_date = commit.last_modified.split(',')[1].replace('GMT','').strip()
        commit_last_modified_for_comparison = datetime.strptime(formatted_date, '%d %b %Y %X')
        answer = commit_last_modified_for_comparison > one_week_ago
    except:
        answer = False

    return answer

def latest_commits_from_prs(repo,prs_to_filter,one_week_ago):
    """
        Gets a list of PRs, filter the ones in where last commit is from last week and returns those commits

        Returns: List of commits (GHE object)
    """
    
    # Create empty list for result
    result = []

    # We would like to get up to half of the prs so calculate how much it is
    max_prs_to_process = ceil(len(list(prs_to_filter)) / 2)

    # Iterate until we found relevant commits in at least half of the PRs or until we went over all of them
    for pr in prs_to_filter:

        # Get head of the PR
        head_sha = pr.head.sha

        # Get commit
        commit = repo.get_commit(sha=head_sha)

        # Check if the commit is relevant, in other words if the commit is from last week
        if is_commit_from_last_week(commit,one_week_ago):
            result.append(commit)

        # If we reach enough, stop the loop
        if len(result) >= max_prs_to_process:
            break
    
    return result

def get_last_week_commits_from_branch(repo,branch,today,one_week_ago):
    """
        Gets the repo object and the name of a branch and return the commits of last week for that branch

        Returns: Commits (GHE object)
    """
    # Get last week commits for branch
    commits = repo.get_commits(sha=branch,since=one_week_ago, until=today)

    return commits