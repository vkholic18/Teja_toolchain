
import unittest
import yaml
import os
import razee_check_duplicate_keys 


doc_no_duplicates = """
apiVersion: deploy.razee.io/v1alpha2
kind: MustacheTemplate
metadata:
  name: deployment-template
  namespace: rias
spec:
  templateEngine: handlebars
  env:
    - name: name1
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_one
          type: jsonString
    - name: name2
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_two
          type: jsonString
    - name: name3
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_three
          type: jsonString                    
"""

doc_with_duplicates = """
apiVersion: deploy.razee.io/v1alpha2
kind: MustacheTemplate
metadata:
  name: deployment-template
  namespace: rias
spec:
  templateEngine: handlebars
  env:
    - name: name1
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_one
          type: jsonString
    - name: name2
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_two
          type: jsonString
    - name: name3
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_one
          type: jsonString                    
"""

doc_lacking_type = """
apiVersion: deploy.razee.io/v1alpha2
kind: MustacheTemplate
metadata:
  name: deployment-template
  namespace: rias
spec:
  templateEngine: handlebars
  env:
    - name: name1
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_one
          type: jsonString
    - name: name2
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_two
"""

doc_same_key_different_resource = """
apiVersion: deploy.razee.io/v1alpha2
kind: MustacheTemplate
metadata:
  name: deployment-template
  namespace: rias
spec:
  templateEngine: handlebars
  env:
    - name: name1
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_one
          type: jsonString
    - name: name2
      valueFrom:
        configMapKeyRef:
          name: zone_globals
          key: key_two
          type: jsonString
    - name: name3
      valueFrom:
        configMapKeyRef:
          name: zone_globals_new
          key: key_one
          type: jsonString                    
"""

def create_file(content,file,isMultiple=False):
    if not isMultiple:
        dct = yaml.safe_load(content)
    else:
        dct = yaml.load_all(content,Loader=yaml.FullLoader)
        dct = list(dct)
    file = open(
        file, "w"
    )
    yaml.dump(dct, file)
    file.close()


class TestRazeeDuplicateKeyRefs(unittest.TestCase):
    def setUp(self):
        global directory
        directory = "genctl-ci-pr/scripts/razee_check_duplicate_keys/"
        

    def test_mtp_no_duplicate_keys(self):
        global directory
        file_name = directory+"doc_no_duplicates.yaml"
        create_file(doc_no_duplicates,file_name)
        actual = razee_check_duplicate_keys.validate_mtp(file_name)
        self.assertEqual(actual,True)
        os.remove(file_name)
    def test_mtp_with_duplicate_keys(self):
        global directory
        file_name = directory+"doc_with_duplicates.yaml"
        create_file(doc_with_duplicates,file_name)
        actual = razee_check_duplicate_keys.validate_mtp(file_name)
        self.assertEqual(actual,False)
        os.remove(file_name)
    def test_mtp_with_missing_type(self):
        global directory
        file_name = directory+"doc_lacking_type.yaml"
        create_file(doc_lacking_type,file_name)
        actual = razee_check_duplicate_keys.validate_mtp(file_name)
        self.assertEqual(actual,False)
        os.remove(file_name)
    def test_mtp_with_same_key_from_different_source(self):
        global directory
        file_name = directory+"doc_with_same_key_different_source.yaml"
        create_file(doc_same_key_different_resource,file_name)
        actual = razee_check_duplicate_keys.validate_mtp(file_name)
        self.assertEqual(actual,True)
        os.remove(file_name)
    

if __name__ == "__main__":
    unittest.main()
