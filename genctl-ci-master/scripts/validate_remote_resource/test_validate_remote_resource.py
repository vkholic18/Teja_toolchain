import unittest
import yaml
import os
from validate_remote_resource import *


content_with_strTemplates = '''
apiVersion: deploy.razee.io/v1alpha2
kind: MustacheTemplate
metadata:
  name: rew-remote-resource-mtp
  namespace: rias
spec:
  env:
  - name: image-version
    valueFrom:
      genericKeyRef:
        apiVersion: deploy.razee.io/v1alpha1
        key: rew-image-version
        kind: FeatureFlagSetLD
        name: rias-ffs-ld
  strTemplates:
  - |
    apiVersion: "deploy.razee.io/v1alpha2"
    kind: RemoteResourceS3
    metadata:
      name: rew-remote-resource
      namespace: rias
    spec:
      auth:
        iam:
          apiKeyRef:
            valueFrom:
              secretKeyRef:
                key: cos-api-key
                name: cos-api-key
                namespace: rias
          grantType: urn:ibm:params:oauth:grant-type:apikey
          responseType: cloud_iam
          url: https://iam.cloud.ibm.com/oidc/token
      requests:
        - options:
            url: "{{{ cos-url }}}/{{{ cos-bucket-name }}}/workspace/{{image-version}}/requirements.txt"
        - options:
            url: "{{{ cos-url }}}/{{{ cos-bucket-name }}}/workspace/{{image-version}}/validate_remote_resource.py"
'''

content_with_templates = '''
apiVersion: deploy.razee.io/v1alpha2
kind: MustacheTemplate
metadata:
spec:
  env:
    - name: image-version
      valueFrom:
        genericKeyRef:
          apiVersion: deploy.razee.io/v1alpha1
          key: keyreact-image-version
          kind: FeatureFlagSetLD
          name: rias-ffs-ld
  templates:
  - apiVersion: "deploy.razee.io/v1alpha2"
    kind: RemoteResourceS3
    metadata:
      name: keyreact-remote-resource
      namespace: rias
    spec:
      auth:
        iam:
          responseType: cloud_iam
          grantType: 'urn:ibm:params:oauth:grant-type:apikey'
          url: 'https://iam.cloud.ibm.com/oidc/token'
          apiKeyRef:
            valueFrom:
              secretKeyRef:
                name: cos-api-key
                key: cos-api-key
                namespace: rias
      requests:
      - options:
          url: "{{{ cos-url }}}/{{{ cos-bucket-name }}}/workspace/{{image-version}}/requirements.txt"
      - options:
          url: "{{{ cos-url }}}/{{{ cos-bucket-name }}}/workspace/{{image-version}}/validate_remote_resource.py"
''' 

def getDict(content):
    dct = yaml.safe_load(content)
    return dct

def create_file(dct):
    file = open("genctl-ci-pr/scripts/validate_remote_resource/sample-remote-resource.yaml",'w')
    yaml.dump(dct,file)
    file.close()
def remove_file():
    os.remove("genctl-ci-pr/scripts/validate_remote_resource/sample-remote-resource.yaml")
  
class TestValidateRemoteResource(unittest.TestCase):
    def test_validate_valid_remote_resource_file(self):
        doc = getDict(content_with_templates)
        create_file(doc)
        res = os.system("python3 genctl-ci-pr/scripts/validate_remote_resource/validate_remote_resource.py --workspaceRazeeDir=genctl-ci-pr/scripts/validate_remote_resource/")
        self.assertEqual(int(res),0)
        remove_file()
    
    def test_validate_invalid_remote_resource_file(self):
        doc = getDict(content_with_templates)
        doc['spec']['templates'][0]['spec'] =  "lol I am dummy"
        create_file(doc)
        res = os.system("python3 genctl-ci-pr/scripts/validate_remote_resource/validate_remote_resource.py --workspaceRazeeDir=genctl-ci-pr/scripts/validate_remote_resource/")
        self.assertNotEqual(int(res),0) 
        remove_file()

    def test_validate_remote_resource_with_invalid_file_path(self):
        doc = getDict(content_with_templates)
        doc['spec']['templates'][0]['spec']['requests'][0]['options']['url'] = "{{{ cos-url }}}/{{{ cos-bucket-name }}}/workspace/{{image-version}}/requirements2.txt"
        create_file(doc)
        res = os.system("python3 genctl-ci-pr/scripts/validate_remote_resource/validate_remote_resource.py --workspaceRazeeDir=genctl-ci-pr/scripts/validate_remote_resource/")
        self.assertNotEqual(int(res),0) 
        remove_file()

    def test_strTemplates_validate_valid_remote_resource_file(self):
        doc = getDict(content_with_strTemplates)
        create_file(doc)
        res = os.system("python3 genctl-ci-pr/scripts/validate_remote_resource/validate_remote_resource.py --workspaceRazeeDir=genctl-ci-pr/scripts/validate_remote_resource/")
        self.assertEqual(int(res),0)
        remove_file()
       

if __name__ == "__main__":
     unittest.main()
