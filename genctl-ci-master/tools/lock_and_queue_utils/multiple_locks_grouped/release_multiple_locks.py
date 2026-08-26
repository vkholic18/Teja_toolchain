import yaml
import sys
import logging

# First get the parameters
locks_file = sys.argv[1] # This should be a path to a YAML file containing section of unclaimed and claimed
locks_to_release = sys.argv[2] # This should be a string space separated representing locks that we need to release

# For logging purposes
logger = logging.getLogger()

# Convert to list
list_of_locks_to_release = locks_to_release.split(' ')

logger.info(f"Will try to release the following locks: {str(list_of_locks_to_release)}")

# Load data of current status
with open(locks_file, 'r') as f:
    locks_data = yaml.load(f, Loader=yaml.SafeLoader)

# Set a variable that will have the list of succesfully relased locks
succesfully_released_locks = []

# Loop over the locks to release; for each one check if is actually claimed and if yes move to unclaimed
for lock_to_release in list_of_locks_to_release:
    logger.info(f"Will try to release lock {lock_to_release}")
    if lock_to_release in locks_data['claimed']:
        locks_data['claimed'].remove(lock_to_release)
        locks_data['unclaimed'].append(lock_to_release)
        succesfully_released_locks.append(lock_to_release)
    else:
        logger.warning(f"Lock {lock_to_release} is not claimed; therefore can't be released...")

if succesfully_released_locks:
    logger.info(f"Succesfully released the following locks: {str(succesfully_released_locks)}")

    with open(locks_file, 'w') as f:
        yaml.dump(locks_data, f)