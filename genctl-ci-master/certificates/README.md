# Certificates

## How to get the certificate
Certificates should be obtained from https://daymvs1.pok.ibm.com/ibmca/certificates.do

## Setup certificate
If needed, utilize a tool (like the openssl command) to convert the downloaded certificate into the needed form.   
e.g. `openssl x509 -in carootcert.der -inform DER -out carootcert.crt`

### Code Example
The `orda_hash.py` script can be viewed to see how a certificate is currently used.
