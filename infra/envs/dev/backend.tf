terraform {
    backend "s3" {
        bucket = "cost-guardian-tf-state-894943009636"
        key = "dev/terraform.tfstate"
        region = "us-west-2"
        dynamodb_table = "cost-guardian-tf-lock"
        encrypt = true
    }   
}
