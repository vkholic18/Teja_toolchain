terraform {
  required_version = "= 1.10.2"

  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = "1.70.1"
    }
  }
}