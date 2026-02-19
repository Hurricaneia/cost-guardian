import boto3

def get_active_regions():
	ec2 = boto3.client("ec2", region_name="us-east-1")
	response = ec2.describe_regions(AllRegions=False)

	return [region["RegionName"] for region in response["Regions"]]
