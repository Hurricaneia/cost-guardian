import boto3
from cost_guardian.rules.base import BaseRule
from cost_guardian.models import Finding

class EBSUnattachedRule(BaseRule):

	RULE_NAME = "UNATTACHED_EBS"

	def run(self):
		findings = []
		ec2 = boto3.client("ec2", region_name=self.region)

		response = ec2.describe_volumes(
			Filters=[{"Name": "status", "Values": ["available"]}]

		)

		for volume in response["Volumes"]:
			size_gb = volume["Size"]
			volume_id = volume["VolumeId"]

			# Rough estimate: assume gp3 ~0.08 per GB-month
			estimated_waste = round(size_gb * 0.08, 2)

			findings.append(
				Finding(
					rule=self.RULE_NAME,
					resource_id=volume_id,
					region=self.region,
					estimated_monthly_waste=estimated_waste,
					details={
						"size_gb": size_gb,
						"volume_type": volume["VolumeType"]
					}
				)
			)

		return findings
