import fileinput
import json
import os
import oyaml as yaml
import re
import urllib3

class vaultLookupException(Exception):
    def __init__(self, message, reserror=None, reqbody=None):
        self.message = message
        self.reserror = reserror
        self.reqbody = reqbody

        if reserror:
            message = f"{message}\nError: {reserror}"
        if reqbody:
            message = f"{message}\nRequest body follows:\n{reqbody}"
        super().__init__(message)

class vaultLookup:
    def __init__(self, secretns):
        self.secretNS = secretns.lower()

        va = "VAULT_ADDR_" + secretns
        self.vaultAddr = os.getenv(va)
        if self.vaultAddr is None:
            raise (vaultLookupException(f"{va} not set in environment"))

        vt = "VAULT_TOKEN_" + secretns
        self.vaultToken = os.getenv(vt)
        if self.vaultToken is None:
            raise (vaultLookupException(f"{vt} not set in environment"))

        vc = "VAULT_CERT_PATH_" + secretns
        self.vaultCertPath = os.getenv(vc)
        if self.vaultCertPath is None:
            raise (vaultLookupException(f"{vc} not set in environment"))

        vp = "INVAULT_PATH_" + secretns
        self.vaultPath = os.getenv(vp)
        if self.vaultPath is None:
            raise (vaultLookupException(f"{vp} not set in environment"))

        vns = "INVAULT_NS_" + secretns
        self.vaultNamespace = os.getenv(vns)
        if self.vaultNamespace is None:
            raise (vaultLookupException(f"{vns} not set in environment"))

        headers = dict()
        headers["X-Vault-Token"] = self.vaultToken
        headers["X-Vault-Namespace"] = self.vaultNamespace
        headers["User-Agent"] = 'secretchecker/v0.1.0'
        url = self.vaultAddr + "/v1/" + self.secretNS

        try:
            self.conn = urllib3.connection_from_url(url, headers=headers, ca_certs=self.vaultCertPath, cert_reqs='REQUIRED')
            print(f"Connected to vault with cert {url}")
        except Exception as e:
            print("Connection with verification by cert caught exception:", e)
            try:
                self.conn = urllib3.connection_from_url(url, headers=headers)
                print(f"Connected to vault without cert {url}")
            except Exception as e:
                print("Connection without verification by cert caught exception:", e)
                exit(1)

    def lookup(self, secretName, subSecrets):
        """
        Need to do the equivalent of
        curl --retry 5 -H "X-Vault-Token: " + self.vaultToken + -H "X-Vault-Namespace: " self.vaultNamespace +
           https:// + self.vaultAddr + /v1/ + self.secretNS + /data/ + self.vaultPath + / + secretName
        If that succeeds, within the result, we want to look up all the subsecrets
        for s in subSecrets:
           if result.s is not None:
               success message
           else:
               error message
        if all secrets are found we return True otherwise we return False
        """

        headers = dict()
        headers["X-Vault-Token"] = self.vaultToken
        headers["X-Vault-Namespace"] = self.vaultNamespace
        headers["User-Agent"] = 'secretchecker/v0.1.0'
        url = self.vaultAddr + "/v1/" + self.secretNS + "/data/" + self.vaultPath + "/"
        # If secret name does not include a namespace prefix, add one.
        # Assume it is in the same namespace as the primary namespace we are searching.
        if secretName.__contains__("/"):
            url = url + secretName
        else:
            url = url + self.secretNS + "/" + secretName
        print(url)

        try:
            res = self.conn.request('GET', url)
            if res.status == 200:
                j = json.loads(res.data)
            else:
                print(f"vault lookup of {url} failed, status {res.status}")
                return False
        except:
            print(f"failed to connect trying to retrieve {url}")
            print("Body:", res.data)
            return False

        allfound = True
        for s in subSecrets:
           try:
              v = j["data"]["data"][s]
           except:
              allfound = False
              v = None
           if v is not None:
               print(f"found {secretName}#{s}")
           else:
               print(f"ERROR: {secretName}#{s} not found!")

        return allfound

class foundSecret:
    def __init__(self, k8sNamespace, secretName, key):
        self.ns = k8sNamespace
        self.name = secretName
        self.keys = [key]
    def addKey(self, candidate):
        if candidate in self.keys:
            return
        self.keys.append(candidate)

def parseYamlFile(yamlFile):
    """
    Takes the file name of the yaml file and returns the
    yaml data in the file in the form of python data structures
    """
    with open(yamlFile) as f:
        return yaml.safe_load(f)

def scanForSecrets(secretsDict, regex, k8sns, template):
    # We look for secretnames and filekeys within lines that match our
    # broader regex pattern (secretAsFile macro lines).
    # These regular expressions limit the secretnames we will find to ones
    # that are simply quoted strings immediately following 'secretName='.
    # Same story for filekeys. Currently we will ignore secretnames or keyfiles
    # of more complexity. For example, a secretname constructed using a
    # razee helper like (concat "path" variable) will not match.
    # Being able to properly know these complex expression values would require us
    # to fully render the templates and that would require much more infrastructure than we
    # currently have in the pipeline. Having full rendering likely would also
    # drastically slow the pipeline, so we only do the simple secrets for now.
    simpleSecretNameDef = re.compile('secretname\s*="\S*"', re.IGNORECASE)
    simpleFilekeyNameDef = re.compile('filekey\s*="\S*"', re.IGNORECASE)

    tlines = template.split('\n')
    for l in tlines:
        m = regex.match(l)
        if m is not None:
            simples = simpleSecretNameDef.search(l)
            simplef = simpleFilekeyNameDef.search(l)

            if simples is None or simplef is None:
                continue

            secretname = simples.group().split('=')[1].strip('"')
            key = simplef.group().split('=')[1].strip('"')

            try:
                current = secretsDict[secretname]
                current.addKey(key)
            except:
                secretsDict[secretname] = foundSecret(k8sns, secretname, key)

#
# Expected input to the script is a list of paths to deploy files. We then scour each file
# looking for secrets in use (see below for search criteria). Once we have collected secrets
# we attempt to find them all in vault.
#
def main():

    vlgenctl = vaultLookup("GENCTL")
    vlrias = vaultLookup("RIAS")

    foundSecrets = dict()

    # Our search for secrets to verify is relatively naive. We check razee files for usage
    # of the vault-agent secretAsFile macro, and assume those usages provide secretname and
    # filekey arguments. Below is our regular expression looking for possible secretAsFile
    # invocations.
    secretsMatch = re.compile('\s*{{>\s*secretAsFile', re.IGNORECASE)

    for line in fileinput.input():
        fn = line.rstrip()
        try:
            y = parseYamlFile(fn)
            md = y["metadata"]
            ns = md["namespace"]
        except:
            print(fn, ": metadata not found?")
            continue

        try:
            tl = y["spec"]["strTemplates"]
        except:
            print(fn, ": strTemplates not found?")
            continue
        for t in tl:
            scanForSecrets(foundSecrets, secretsMatch, ns, t)

    allfound = True
    for k in foundSecrets:
        if foundSecrets[k].ns == "rias":
            found = vlrias.lookup(k, foundSecrets[k].keys)
            if not found:
                allfound = False
        elif foundSecrets[k].ns == "genctl":
            found = vlgenctl.lookup(k, foundSecrets[k].keys)
            if not found:
                allfound = False
        else:
            # Not sure which vault sub-section it lives in so we will try
            # both. Try rias first, that seems to be the side that more often
            # contains secrets in other namespaces.
            found = vlrias.lookup(k, foundSecrets[k].keys)
            if not found:
                found = vlgenctl.lookup(k, foundSecrets[k].keys)

            if not found:
                allfound = False

    if allfound:
        exit(0)
    else:
        exit(1)

if __name__ == "__main__":
    main()
