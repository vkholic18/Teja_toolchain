variable "ibmcloud_api_key" {
  sensitive = true
  type      = string
}

variable "region" {
  type    = string
  default = "us-south"
}

