from os import system
from kubernetes import client, config
from kubernetes.client.exceptions import ApiException
import sys

def connect_to_cluster():
    contexts, active_context = config.list_kube_config_contexts()
    if not contexts:
        print("Cannot find context in kube config file")
        return
    config.load_kube_config(context=active_context['name'])
    print("Using {0} as the context to check for the secrets".format(active_context['name']))
    return active_context

def validate_razee_lock_status():
    print("Checking Razee lock status...")
    active_context = connect_to_cluster()
    v1 = client.CoreV1Api()
    try:
        cfm = v1.read_namespaced_config_map(name="razeedeploy-config",namespace="razee")
        res = cfm.data['lock-cluster']
        if res == 'false':
            print("Validation successful: Razee is unlocked in cluster:",active_context['name'])
            sys.exit(0)
        else:
            print("Validation failed: Razee is locked in cluster:",active_context['name'])
            sys.exit(1)

    except ApiException as e:
        print("Error occurred:",e)
        if e.status == 404:
            print("Failed to find razeedeploy-config. Razee is considered unlocked in cluster:",active_context['name'])
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        print("Error occurred:",e)
        sys.exit(1)

def main():
    validate_razee_lock_status()

if __name__ == "__main__":
    main()