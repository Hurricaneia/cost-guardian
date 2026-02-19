from cost_guardian.rules.ebs_unattached import EBSUnattachedRule
from cost_guardian.utils.regions import get_active_regions
from cost_guardian.rules.eip_unassociated import EIPUnassociatedRule

class CostEngine:

	def __init__(self):
		self.rule_classes = [
			EBSUnattachedRule,
			EIPUnassociatedRule,
		]

	def run(self):
		all_findings = []
		regions = get_active_regions()

		for region in regions:
			for rule_class in self.rule_classes:
				rule = rule_class(region)
				findings = rule.run()
				all_findings.extend(findings)

		total_estimated_waste = round (
			sum(f.estimated_monthly_waste for f in all_findings),
			2
		)

		return {
			"regions_scanned": regions,
			"total_estimated_monthly_waste": total_estimated_waste,
			"findings": [f.to_dict() for f in all_findings]
		}
