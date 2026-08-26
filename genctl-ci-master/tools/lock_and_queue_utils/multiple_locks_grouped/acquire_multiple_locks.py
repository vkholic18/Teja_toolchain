import yaml
import sys
import logging

# First get the parameters
locks_file = sys.argv[1] # This should be a path to a YAML file containing section of unclaimed and claimed
locks_to_acquire = sys.argv[2] # This should be a string space separated representing locks that we need to acquire


# For logging purposes
logger = logging.getLogger()

# Convert to list
list_of_locks_to_acquire = locks_to_acquire.split(' ')

logger.info(f"Will try to acquire the following locks: {str(list_of_locks_to_acquire)}")

# Load data of current status
with open(locks_file, 'r') as f:
    locks_data = yaml.load(f, Loader=yaml.SafeLoader)

# First check if there is any available lock; if not then just exit 1
if locks_data['unclaimed']:
    
    # Loop over the locks to acquire; for each one check if unclaimed and if yes move to claimed
    for lock_to_acquire in list_of_locks_to_acquire:
        logger.info(f"Will check if lock {lock_to_acquire} is unclaimed")
        if lock_to_acquire in locks_data['unclaimed']:
            logger.info(f"Lock {lock_to_acquire} is unclaimed")
            locks_data['unclaimed'].remove(lock_to_acquire)
            locks_data['claimed'].append(lock_to_acquire)
        else:
            if lock_to_acquire in locks_data['claimed']:
                logger.error(f"Lock {lock_to_acquire} is already claimed...")
            else:
                logger.error(f"Lock {lock_to_acquire} is neither claimed, nor unclaimed...")
                logger.error(f"Seems that lock does not exists...")
            sys.exit(1)


    # If we managed to reach here then all the locks were available, then we make the actual change in the file
    logger.info(f"Succesfully acquired all the requested NGDC locks: {str(list_of_locks_to_acquire)}")
    
    with open(locks_file, 'w') as f:
        yaml.dump(locks_data, f)
else:
    print("There are no locks unclaimed")
    sys.exit(1)