from dataclasses import dataclass, asdict

@dataclass
class Finding:
	rule: str
	resource_id: str
	region: str
	estimated_monthly_waste: float
	details: dict

	def to_dict(self):
		return asdict(self)
