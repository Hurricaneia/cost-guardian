import boto3
from cost_guardian.rules.base import BaseRule
from cost_guardian.models import Finding

class EIPUnassociatedRule(BaseRule):

        RULE_NAME= "UNASSOCIATED_EIP"

        def run(self):
                findings = []
                ec2 = boto3.client("ec2", region_name=self.region)

                response = ec2.describe_addresses()

                for address in response["Addresses"]:
                        #IF no association ID, its not attached
                        if "AssociationId" not in address:
                                allocation_id = address.get("AllocationId", "unknown")

                                #EIP idle cost approx 0.005/hr = $3.60/month
                                estimated_waste = 3.60

                                findings.append(
                                        Finding(
                                                rule=self.RULE_NAME,
                                                resource_id=allocation_id,
                                                region=self.region,
                                                estimated_monthly_waste=estimated_waste,
                                                details={
                                                        "public_ip": address.get("PublicIp")
                                                }
                                        )
                                )
                return findings

